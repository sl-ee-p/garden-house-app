import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// Small key/value store kept as one JSON file in the app's documents
/// directory.
///
/// Replaces shared_preferences, whose Android side is called through JNI and
/// broke in R8-minified release builds (NoSuchMethodError on launch).
class LocalStore {
  LocalStore._(this._file, this._data);

  static Future<LocalStore>? _instance;

  static Future<LocalStore> get instance => _instance ??= _open();

  static Future<LocalStore> _open() async {
    final dir = await getApplicationDocumentsDirectory();
    return open(File('${dir.path}/settings.json'));
  }

  /// Opens the store kept in [file]; [instance] uses the app's settings file.
  ///
  /// An unreadable or corrupt file is moved aside to `<file>.bad` and the
  /// store starts empty, so the next write can't destroy what's left of it.
  @visibleForTesting
  static Future<LocalStore> open(File file) async {
    var data = <String, dynamic>{};
    try {
      if (await file.exists()) {
        data = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      }
    } on Object catch (e) {
      debugPrint('Ignoring unreadable ${file.path}: $e');
      try {
        await file.rename('${file.path}.bad');
      } on FileSystemException catch (e) {
        debugPrint('Could not move ${file.path} aside: $e');
      }
    }
    return LocalStore._(file, data);
  }

  final File _file;
  final Map<String, dynamic> _data;
  Future<void> _writing = Future.value();

  /// The string stored under [key], or null if there is none (or the value
  /// isn't a string).
  String? getString(String key) => switch (_data[key]) {
    final String value => value,
    _ => null,
  };

  /// Updates the value and writes the file; writes are serialized, and each
  /// goes to a temp file first so a crash can't leave half a file behind.
  Future<void> setString(String key, String value) {
    _data[key] = value;
    final json = jsonEncode(_data);
    return _writing = _writing
        .then((_) async {
          final tmp = File('${_file.path}.tmp');
          await tmp.writeAsString(json, flush: true);
          await tmp.rename(_file.path);
        })
        .catchError((Object e) => debugPrint('Saving settings failed: $e'));
  }
}
