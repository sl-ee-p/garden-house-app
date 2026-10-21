import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:model_viewer_plus/model_viewer_plus.dart';
import 'package:webview_flutter/webview_flutter.dart';

import 'asset_server.dart';
import 'house_model.dart';

/// Drives a [HouseViewer] from Flutter.
class HouseViewerController {
  _HouseViewerState? _state;

  /// Turns the camera around the house: [theta] is the horizontal angle,
  /// [phi] the angle from straight above (90 = eye level), both in degrees.
  void setOrbit(double theta, double phi) => _state?._run(
    'setOrbit(${theta.toStringAsFixed(2)}, ${phi.toStringAsFixed(2)})',
  );

  /// Like [setOrbit], but glides there and stops the auto-rotation.
  void animateOrbit(double theta, double phi) => _state?._run(
    'animateOrbit(${theta.toStringAsFixed(2)}, ${phi.toStringAsFixed(2)})',
  );

  /// Back to the initial view, auto-rotating.
  void resetView() => _state?._run('resetView()');

  /// Shows or hides the width/depth/height lines (interactive viewer only).
  void setDimensions(bool visible) => _state?._run('setDimensions($visible)');

  /// An inactive viewer is hidden in the page and stops rendering; use it
  /// while another screen covers the viewer.
  void setActive(bool active) => _state?._run('setActive($active)');

  /// PNG of the current render, or null if the model hasn't loaded yet or
  /// the render couldn't be captured (see [ViewerSnapshots]). The background
  /// is transparent for a non-interactive viewer and the garden for an
  /// interactive one.
  Future<Uint8List?> snapshot() async => _state?._snapshot();
}

/// Snapshot requests to the viewer's page, and their answers.
///
/// The page answers asynchronously through the JavaScript channel, so a
/// request whose answer never comes (the script failed to run, the WebView
/// was torn down) must not leave the caller waiting forever: share and quote
/// stay disabled until it completes. Every request therefore completes, with
/// null when the script can't run, the page reports an error, the answer
/// can't be decoded, or nothing arrives within [timeout].
@visibleForTesting
class ViewerSnapshots {
  ViewerSnapshots(
    this._runJavaScript, {
    this.timeout = const Duration(seconds: 10),
  });

  final Future<void> Function(String js) _runJavaScript;
  final Duration timeout;
  Completer<Uint8List?>? _pending;

  /// Asks the page for a PNG. Requests made while one is pending share it.
  Future<Uint8List?> request() {
    final pending = _pending;
    if (pending != null) return pending.future;
    final completer = _pending = Completer<Uint8List?>();
    _runJavaScript('snapshot()').catchError((Object e) {
      debugPrint('Snapshot script failed: $e');
      _complete(completer, null);
    });
    return completer.future.timeout(
      timeout,
      onTimeout: () {
        debugPrint('No snapshot from the viewer after $timeout');
        _complete(completer, null);
        return null;
      },
    );
  }

  /// Handles the page's `{type: 'snapshot'}` message: `data` is a PNG data
  /// URL, or `error` says why there is none.
  void onMessage(Map<String, dynamic> msg) {
    final pending = _pending;
    if (pending == null) return;
    Uint8List? png;
    if (msg['data'] case final String data) {
      try {
        png = base64Decode(data.substring(data.indexOf(',') + 1));
      } on FormatException catch (e) {
        debugPrint('Unreadable snapshot: $e');
      }
    } else {
      debugPrint('Snapshot failed in the viewer: ${msg['error']}');
    }
    _complete(pending, png);
  }

  /// Completes a pending request with null, e.g. when the viewer goes away.
  void cancel() {
    if (_pending case final pending?) _complete(pending, null);
  }

  void _complete(Completer<Uint8List?> completer, Uint8List? png) {
    if (identical(_pending, completer)) _pending = null;
    if (!completer.isCompleted) completer.complete(png);
  }
}

/// 3D view of the garden house with the model's current paints.
///
/// The WebView is created once and loads the bundled model; paint changes are
/// applied to its materials through model-viewer's JS API. (Reloading a baked
/// GLB on every change meant tearing down and rebuilding the whole WebView.)
class HouseViewer extends StatefulWidget {
  const HouseViewer({
    super.key,
    required this.model,
    this.controller,
    bool? interactive,
    this.initialOrbit = '35deg 75deg auto',
  }) : interactive = interactive ?? controller == null;

  final HouseModel model;
  final HouseViewerController? controller;

  /// An interactive viewer stands in the garden; the user orbits it and it
  /// auto-rotates. Otherwise it ignores touches, has a transparent
  /// background, and is moved only through [controller]. Defaults to
  /// interactive only without a controller.
  final bool interactive;
  final String initialOrbit;

  /// Background of the interactive viewer, projected as ground and sky.
  static const skybox = 'assets/env/garden.jpg';

  /// Lighting: the HDR of the same place as [skybox].
  static const environment = 'assets/env/garden.hdr';

  @override
  State<HouseViewer> createState() => _HouseViewerState();
}

class _HouseViewerState extends State<HouseViewer> {
  static const _channel = 'HouseViewer';

  // Runs after the <model-viewer> element; `paints` maps material name to
  // {c: linear RGBA, m: metallic, r: roughness, t: texture URL or null,
  // n: its normal map URL}.
  static const _js =
      '''
(() => {
  const viewer = document.querySelector('model-viewer');
  const send = (msg) => $_channel.postMessage(JSON.stringify(msg));
  const initialOrbit = viewer.cameraOrbit;
  // Filmic: keeps highlights and shadows out of the flat, plasticky look of
  // the default curve.
  viewer.toneMapping = 'aces';
  let paints = {};
  const textures = {};  // url -> Promise<Texture>
  const shown = {};  // material name -> texture URL set on it
  const modelNormals = {};  // material name -> the model's own normal map
  const load = async (url) => {
    textures[url] ??= viewer.createTexture(url);
    try {
      const texture = await textures[url];
      // Pre-mirrored tiles (tools/make_textures.py): plain repeat is seamless.
      texture.sampler.setWrapS(10497);
      texture.sampler.setWrapT(10497);
      return texture;
    } catch (e) {
      delete textures[url];
      return null;
    }
  };
  // Loads a texture and its normal map and sets them once both are ready; a
  // load superseded by another pick meanwhile is dropped.
  const loadTexture = async (material, url, normalUrl) => {
    const [texture, normals] = await Promise.all([load(url), normalUrl && load(normalUrl)]);
    if (!texture) return;
    if (paints[material.name]?.t !== url || shown[material.name] === url) return;
    material.pbrMetallicRoughness.baseColorTexture.setTexture(texture);
    material.pbrMetallicRoughness.setBaseColorFactor([1, 1, 1, 1]);
    if (normals) material.normalTexture.setTexture(normals);
    shown[material.name] = url;
  };
  const apply = () => {
    if (!viewer.model) return;
    for (const material of viewer.model.materials) {
      const p = paints[material.name];
      if (!p) continue;
      const pbr = material.pbrMetallicRoughness;
      if (!(material.name in modelNormals)) {
        modelNormals[material.name] = material.normalTexture?.texture ?? null;
      }
      if (!p.t && shown[material.name]) {
        pbr.baseColorTexture.setTexture(null);
        material.normalTexture.setTexture(modelNormals[material.name]);
        delete shown[material.name];
      }
      // While another texture is shown it stays until the new one is ready;
      // without one, the flat color shows meanwhile. Never a white flash.
      if (!shown[material.name]) pbr.setBaseColorFactor(p.c);
      pbr.setMetallicFactor(p.m);
      pbr.setRoughnessFactor(p.r);
      if (p.t && shown[material.name] !== p.t) loadTexture(material, p.t, p.n);
    }
  };
  window.setPaints = (p) => { paints = p; apply(); };
  window.setOrbit = (theta, phi) => {
    viewer.cameraOrbit = theta + 'deg ' + phi + 'deg auto';
    viewer.jumpCameraToGoal();
  };
  // Glides to a view and stops the turntable there.
  window.animateOrbit = (theta, phi) => {
    viewer.autoRotate = false;
    viewer.resetTurntableRotation(0);
    viewer.cameraOrbit = theta + 'deg ' + phi + 'deg auto';
    viewer.fieldOfView = 'auto';
  };
  window.resetView = () => {
    viewer.resetTurntableRotation(0);
    viewer.cameraOrbit = initialOrbit;
    viewer.fieldOfView = 'auto';
    viewer.autoRotate = true;
  };
  // Hidden elements stop rendering, so a covered preview costs nothing.
  window.setActive = (active) => {
    viewer.style.display = active ? '' : 'none';
  };
  // toDataURL throws e.g. on a lost WebGL context; Dart still needs an answer.
  window.snapshot = () => {
    try {
      send({type: 'snapshot', data: viewer.toDataURL('image/png')});
    } catch (e) {
      send({type: 'snapshot', error: String(e)});
    }
  };

  // Dimension lines between bounding-box corners, after modelviewer.dev's
  // dimensions example. The house is modeled in meters.
  const lines = viewer.querySelectorAll('#dimLines line');
  const hotspot = (name) => viewer.queryHotspot('hotspot-' + name);
  const drawLine = (line, from, to, label) => {
    const a = hotspot(from), b = hotspot(to), dim = hotspot(label);
    if (!a || !b) return;
    line.setAttribute('x1', a.canvasPosition.x);
    line.setAttribute('y1', a.canvasPosition.y);
    line.setAttribute('x2', b.canvasPosition.x);
    line.setAttribute('y2', b.canvasPosition.y);
    const hidden = dim && !dim.facingCamera;
    line.classList.toggle('hide', hidden);
    viewer.querySelector('[slot="hotspot-' + label + '"]').classList.toggle('hide', hidden);
  };
  const drawDimensions = () => {
    if (!lines.length || viewer.classList.contains('dimensions-off')) return;
    drawLine(lines[0], 'dot+X-Y+Z', 'dot+X-Y-Z', 'dim+X-Y');
    drawLine(lines[1], 'dot+X-Y-Z', 'dot+X+Y-Z', 'dim+X-Z');
    drawLine(lines[2], 'dot+X+Y-Z', 'dot-X+Y-Z', 'dim+Y-Z');
    drawLine(lines[3], 'dot-X+Y-Z', 'dot-X-Y-Z', 'dim-X-Z');
    drawLine(lines[4], 'dot-X-Y-Z', 'dot-X-Y+Z', 'dim-X-Y');
  };
  const placeDimensions = () => {
    if (!lines.length) return;
    const c = viewer.getBoundingBoxCenter();
    const s = viewer.getDimensions();
    const x = s.x / 2, y = s.y / 2, z = s.z / 2;
    const put = (name, px, py, pz) =>
      viewer.updateHotspot({name: 'hotspot-' + name, position: px + ' ' + py + ' ' + pz});
    put('dot+X-Y+Z', c.x + x, c.y - y, c.z + z);
    put('dot+X-Y-Z', c.x + x, c.y - y, c.z - z);
    put('dot+X+Y-Z', c.x + x, c.y + y, c.z - z);
    put('dot-X+Y-Z', c.x - x, c.y + y, c.z - z);
    put('dot-X-Y-Z', c.x - x, c.y - y, c.z - z);
    put('dot-X-Y+Z', c.x - x, c.y - y, c.z + z);
    put('dim+X-Y', c.x + x * 1.1, c.y - y, c.z);
    put('dim+X-Z', c.x + x * 1.1, c.y, c.z - z * 1.1);
    put('dim+Y-Z', c.x, c.y + y * 1.1, c.z - z * 1.1);
    put('dim-X-Z', c.x - x * 1.1, c.y, c.z - z * 1.1);
    put('dim-X-Y', c.x - x * 1.1, c.y - y, c.z);
    const cm = (v) => Math.round(v * 100) + ' cm';
    const label = (name, text) =>
      viewer.querySelector('[slot="hotspot-' + name + '"]').textContent = text;
    label('dim+X-Y', cm(s.z));
    label('dim+X-Z', cm(s.y));
    label('dim+Y-Z', cm(s.x));
    label('dim-X-Z', cm(s.y));
    label('dim-X-Y', cm(s.z));
  };
  window.setDimensions = (on) => {
    viewer.classList.toggle('dimensions-off', !on);
    drawDimensions();
  };
  viewer.addEventListener('camera-change', drawDimensions);

  viewer.addEventListener('progress', (e) =>
    send({type: 'progress', value: e.detail.totalProgress}));
  viewer.addEventListener('load', () => {
    apply();
    placeDimensions();
    // Hotspot screen positions are known after the next frame.
    requestAnimationFrame(drawDimensions);
    send({type: 'loaded'});
  });
})();
''';

  static const _css = '''
model-viewer { --poster-color: transparent; }
.dim {
  background: rgba(255, 255, 255, 0.92);
  border-radius: 8px;
  border: none;
  box-shadow: 0 1px 4px rgba(0, 0, 0, 0.3);
  color: #1b3a26;
  font: 600 12px/1 system-ui, sans-serif;
  padding: 4px 6px;
  pointer-events: none;
}
.dot { display: none; }
.dim, #dimLines { transition: opacity .3s; }
.dimensions-off .dim, .dimensions-off #dimLines, .dim.hide { opacity: 0; }
#dimLines { position: absolute; inset: 0; width: 100%; height: 100%; pointer-events: none; }
#dimLines line { stroke: #fff; stroke-width: 2; stroke-dasharray: 4; filter: drop-shadow(0 0 1px rgba(0,0,0,.6)); }
#dimLines line.hide { display: none; }
''';

  // Hotspots and lines for the dimensions, positioned by _js.
  static const _dimensionsHtml = '''
<button slot="hotspot-dot+X-Y+Z" class="dot"></button>
<button slot="hotspot-dot+X-Y-Z" class="dot"></button>
<button slot="hotspot-dot+X+Y-Z" class="dot"></button>
<button slot="hotspot-dot-X+Y-Z" class="dot"></button>
<button slot="hotspot-dot-X-Y-Z" class="dot"></button>
<button slot="hotspot-dot-X-Y+Z" class="dot"></button>
<button slot="hotspot-dim+X-Y" class="dim" data-normal="1 0 0"></button>
<button slot="hotspot-dim+X-Z" class="dim" data-normal="1 0 0"></button>
<button slot="hotspot-dim+Y-Z" class="dim" data-normal="0 1 0"></button>
<button slot="hotspot-dim-X-Z" class="dim" data-normal="-1 0 0"></button>
<button slot="hotspot-dim-X-Y" class="dim" data-normal="-1 0 0"></button>
<svg id="dimLines" xmlns="http://www.w3.org/2000/svg">
<line></line><line></line><line></line><line></line><line></line>
</svg>
''';

  WebViewController? _web;
  bool _loaded = false;
  final _progress = ValueNotifier<double>(0);
  late final _snapshots = ViewerSnapshots(
    (js) => _web?.runJavaScript(js) ?? Future.error(StateError('No WebView')),
  );

  /// Serves the skybox, the lighting and the panel textures.
  AssetServer? _server;

  /// Built once (ModelViewer ignores widget updates anyway), after the
  /// asset server is up.
  Widget? _viewer;

  @override
  void initState() {
    super.initState();
    widget.controller?._state = this;
    widget.model.addListener(_pushPaints);
    AssetServer.instance.then((server) {
      if (mounted) setState(() => _viewer = _build(_server = server));
    });
  }

  Widget _build(AssetServer server) {
    final interactive = widget.interactive;
    return ModelViewer(
      src: HouseModel.asset,
      alt: 'Garden House',
      backgroundColor: Colors.transparent,
      cameraControls: interactive,
      autoRotate: interactive,
      autoRotateDelay: 3000,
      interpolationDecay: interactive ? null : 1,
      shadowIntensity: 1,
      shadowSoftness: 1,
      skyboxImage: interactive ? server.url(HouseViewer.skybox) : null,
      // Daylight from the park's HDR, for the photo overlay too: an outdoor
      // scene, unlike model-viewer's neutral studio light.
      environmentImage: server.url(HouseViewer.environment),
      exposure: 1,
      interactionPrompt: InteractionPrompt.none,
      cameraOrbit: widget.initialOrbit,
      minCameraOrbit: 'auto 20deg auto',
      // Interactive: stay above the projected ground and close enough for
      // it to look right.
      maxCameraOrbit: interactive ? 'auto 85deg 14m' : 'auto 90deg auto',
      innerModelViewerHtml: interactive ? _dimensionsHtml : null,
      relatedCss: _css,
      relatedJs: _js,
      javascriptChannels: {
        JavascriptChannel(_channel, onMessageReceived: _onMessage),
      },
      onWebViewCreated: (controller) => _web = controller,
    );
  }

  @override
  void dispose() {
    widget.model.removeListener(_pushPaints);
    if (widget.controller?._state == this) widget.controller!._state = null;
    _snapshots.cancel();
    _progress.dispose();
    super.dispose();
  }

  void _onMessage(JavaScriptMessage message) {
    // The page can still post while this state is being disposed.
    if (!mounted) return;
    final Map<String, dynamic> msg;
    try {
      msg = jsonDecode(message.message) as Map<String, dynamic>;
    } on Object catch (e) {
      debugPrint('Ignoring viewer message ${message.message}: $e');
      return;
    }
    switch (msg['type']) {
      case 'progress':
        if (msg['value'] case final num value) {
          _progress.value = value.toDouble();
        }
      case 'loaded':
        setState(() => _loaded = true);
        _pushPaints();
      case 'snapshot':
        _snapshots.onMessage(msg);
    }
  }

  /// Runs [js] in the page once the model has loaded. Failures (e.g. the
  /// WebView is gone) are logged: they only affect this one command.
  void _run(String js) {
    final web = _web;
    if (!_loaded || web == null) return;
    web.runJavaScript(js).catchError((Object e) {
      debugPrint('Viewer script failed ($js): $e');
    });
  }

  Future<Uint8List?> _snapshot() {
    if (!_loaded || _web == null) return Future.value(null);
    return _snapshots.request();
  }

  void _pushPaints() {
    final paints = {
      for (final MapEntry(key: part, value: paint)
          in widget.model.paints.entries)
        part.materialName: {
          'c': paint.linearRgba,
          'm': paint.metallic,
          'r': paint.roughness,
          't': switch (paint.textureAsset) {
            final key? => _server?.url(key),
            null => null,
          },
          'n': switch (paint.normalAsset) {
            final key? => _server?.url(key),
            null => null,
          },
        },
    };
    _run('setPaints(${jsonEncode(paints)})');
  }

  @override
  Widget build(BuildContext context) {
    final viewer = _viewer;
    if (!widget.interactive) return IgnorePointer(child: viewer);
    final scheme = Theme.of(context).colorScheme;
    return Stack(
      fit: StackFit.expand,
      children: [
        ?viewer,
        // Covers the blank WebView until the house is in the garden.
        IgnorePointer(
          ignoring: _loaded,
          child: AnimatedOpacity(
            opacity: _loaded ? 0 : 1,
            duration: const Duration(milliseconds: 400),
            child: ColoredBox(
              color: scheme.surfaceContainerHighest,
              child: Center(
                child: SizedBox(
                  width: 160,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.cottage_outlined,
                        size: 48,
                        color: scheme.primary,
                      ),
                      const SizedBox(height: 16),
                      ValueListenableBuilder(
                        valueListenable: _progress,
                        builder: (context, value, _) => LinearProgressIndicator(
                          value: value > 0 && value < 1 ? value : null,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
