import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import 'glb_recolor.dart';
import 'local_store.dart';

/// Paints for every part; what favorites store and undo restores.
typedef HouseConfig = Map<HousePart, Paint>;

Map<String, dynamic> configToJson(HouseConfig config) => {
  for (final MapEntry(key: part, value: paint) in config.entries)
    part.name: paint.toJson(),
};

/// Parts missing from [json], unknown names and malformed paints are
/// skipped, so one bad entry doesn't lose the rest of a saved configuration.
HouseConfig configFromJson(Map<String, dynamic> json) => {
  for (final part in HousePart.values)
    if (json[part.name] case final Map<String, dynamic> paint)
      part: ?_tryPaint(paint),
};

Paint? _tryPaint(Map<String, dynamic> json) {
  try {
    return Paint.fromJson(json);
  } on TypeError catch (e) {
    debugPrint('Ignoring saved paint $json: $e');
    return null;
  }
}

/// Holds the current configuration. The 3D preview recolors the bundled model
/// live; the AR view needs a file, which [exportGlb] bakes on demand.
///
/// Changes can be undone, and are saved so the next launch starts from them.
class HouseModel extends ChangeNotifier {
  /// [loadAsset] reads bundled files (textures); defaults to the root bundle.
  @visibleForTesting
  HouseModel(
    this._recolorer,
    this._dir, [
    this._store,
    Future<Uint8List> Function(String key)? loadAsset,
  ]) : _loadAsset = loadAsset ?? _loadBundled;

  static Future<Uint8List> _loadBundled(String key) async =>
      (await rootBundle.load(key)).buffer.asUint8List();

  /// Bundled model, shown by the 3D preview.
  static const asset = 'assets/models/garden_house.glb';

  /// Real size of the garden house, in meters (largest dimension of the GLB).
  static const realSizeMeters = 2.64;

  static const _lastConfigKey = 'last_config';
  static const _maxHistory = 30;

  final GlbRecolorer _recolorer;
  final Directory _dir;
  final LocalStore? _store;
  final Future<Uint8List> Function(String key) _loadAsset;
  final _history = <HouseConfig>[];
  Timer? _saveTimer;
  int _revision = 0;
  String? _exported;
  Map<HousePart, Paint>? _exportedPaints;

  final paints = <HousePart, Paint>{
    HousePart.structure: const Paint(0x8B4513),
    HousePart.panels: const Paint(0xF5F5F5),
  };

  static Future<HouseModel> load() async {
    final bytes = (await rootBundle.load(asset)).buffer.asUint8List();
    final dir = await getApplicationDocumentsDirectory();
    // Files baked by previous runs.
    await for (final f in dir.list()) {
      if (f is File && RegExp(r'/house_\d+\.glb$').hasMatch(f.path)) {
        await f.delete();
      }
    }
    final store = await LocalStore.instance;
    final model = HouseModel(GlbRecolorer(bytes), dir, store);
    final saved = store.getString(_lastConfigKey);
    if (saved != null) {
      try {
        model.paints.addAll(
          configFromJson(jsonDecode(saved) as Map<String, dynamic>),
        );
      } on Object catch (e) {
        debugPrint('Ignoring saved configuration: $e');
      }
    }
    return model;
  }

  bool get canUndo => _history.isNotEmpty;

  void setColor(HousePart part, int rgb) =>
      applyConfig({...paints, part: paints[part]!.withColor(rgb)});

  /// Gives [part] the texture [id], with [fallbackColor] as its color.
  void setTexture(HousePart part, String id, int fallbackColor) => applyConfig({
    ...paints,
    part: paints[part]!.withTexture(id, fallbackColor),
  });

  void setFinish(HousePart part, Finish finish) =>
      applyConfig({...paints, part: paints[part]!.withFinish(finish)});

  /// Applies [config] (any subset of parts) as one undoable step.
  void applyConfig(HouseConfig config) {
    final next = {...paints, ...config};
    if (mapEquals(next, paints)) return;
    _history.add(Map.of(paints));
    if (_history.length > _maxHistory) _history.removeAt(0);
    _set(next);
  }

  void undo() {
    if (_history.isNotEmpty) _set(_history.removeLast());
  }

  void _set(HouseConfig config) {
    paints.addAll(config);
    notifyListeners();
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 500), _save);
  }

  Future<void> _save() async {
    _saveTimer?.cancel();
    _saveTimer = null;
    await _store?.setString(_lastConfigKey, jsonEncode(configToJson(paints)));
  }

  /// Saves now if a change is still waiting for its (debounced) save, e.g.
  /// when the app goes to the background and may be killed.
  Future<void> flush() async {
    if (_saveTimer?.isActive ?? false) await _save();
  }

  @override
  void dispose() {
    // Not just cancelling the timer: the last change would never be saved.
    flush();
    super.dispose();
  }

  /// Writes a GLB with the current paints and returns its path. Reuses the
  /// last file if nothing changed since.
  Future<String> exportGlb() async {
    final exported = _exported;
    if (exported != null && mapEquals(_exportedPaints, paints)) return exported;
    // A new file name per revision defeats ARCore caching.
    final file = File('${_dir.path}/house_${++_revision}.glb');
    final snapshot = Map.of(paints);
    final images = <String, Uint8List>{};
    for (final paint in snapshot.values) {
      for (final key in [?paint.textureAsset, ?paint.normalAsset]) {
        try {
          images[key] = await _loadAsset(key);
        } on Object catch (e) {
          // E.g. a finish saved by a version that still had it: the
          // recolorer falls back to the paint's flat color.
          debugPrint('Exporting without $key: $e');
        }
      }
    }
    await file.writeAsBytes(
      _recolorer.build(snapshot, images: images),
      flush: true,
    );
    if (exported != null) {
      final old = File(exported);
      if (await old.exists()) await old.delete();
    }
    _exportedPaints = snapshot;
    return _exported = file.path;
  }
}
