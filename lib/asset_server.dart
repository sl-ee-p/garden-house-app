import 'dart:io';

import 'package:flutter/services.dart';

/// Serves bundled assets over loopback HTTP, for the WebView.
///
/// model_viewer_plus's own proxy only serves the model, so other files the
/// page needs (the skybox, the panel textures) come from here.
class AssetServer {
  AssetServer._(this._server) {
    _server.listen(_handle);
  }

  static Future<AssetServer>? _instance;

  static Future<AssetServer> get instance => _instance ??= HttpServer.bind(
    InternetAddress.loopbackIPv4,
    0,
  ).then(AssetServer._);

  final HttpServer _server;

  static const _types = {
    'jpg': 'image/jpeg',
    'png': 'image/png',
    'hdr': 'application/octet-stream',
  };

  /// URL of the bundled asset [key] (e.g. `assets/env/garden.jpg`).
  String url(String key) => 'http://127.0.0.1:${_server.port}/$key';

  Future<void> _handle(HttpRequest request) async {
    final response = request.response
      ..headers.add('Access-Control-Allow-Origin', '*');
    final key = request.uri.path.substring(1);
    try {
      if (!key.startsWith('assets/')) throw const FormatException();
      final data = await rootBundle.load(key);
      response
        ..headers.contentType = ContentType.parse(
          _types[key.split('.').last] ?? 'application/octet-stream',
        )
        ..headers.contentLength = data.lengthInBytes
        ..add(data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes));
    } catch (_) {
      response.statusCode = HttpStatus.notFound;
    }
    await response.close();
  }
}
