import 'package:ar_flutter_plugin_2/datatypes/config_planedetection.dart';
import 'package:ar_flutter_plugin_2/datatypes/hittest_result_types.dart';
import 'package:ar_flutter_plugin_2/datatypes/node_types.dart';
import 'package:ar_flutter_plugin_2/ar_flutter_plugin.dart';
import 'package:ar_flutter_plugin_2/managers/ar_anchor_manager.dart';
import 'package:ar_flutter_plugin_2/managers/ar_location_manager.dart';
import 'package:ar_flutter_plugin_2/managers/ar_object_manager.dart';
import 'package:ar_flutter_plugin_2/managers/ar_session_manager.dart';
import 'package:ar_flutter_plugin_2/models/ar_anchor.dart';
import 'package:ar_flutter_plugin_2/models/ar_hittest_result.dart';
import 'package:ar_flutter_plugin_2/models/ar_node.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:vector_math/vector_math_64.dart' hide Colors;

import 'house_model.dart';
import 'photo_screen.dart';

/// Camera view where the user taps a surface to drop the garden house at its
/// real size, then drags / twists to position it.
class ArScreen extends StatefulWidget {
  const ArScreen({super.key, required this.model, required this.glbPath});

  /// For falling back to [PhotoScreen] if AR can't start.
  final HouseModel model;

  /// GLB with the configured paints, from [HouseModel.exportGlb].
  final String glbPath;

  @override
  State<ArScreen> createState() => _ArScreenState();
}

class _ArScreenState extends State<ArScreen> {
  ARSessionManager? _session;
  ARObjectManager? _objects;
  ARAnchorManager? _anchors;
  ARAnchor? _anchor;
  late final Future<PermissionStatus> _camera = Permission.camera.request();
  bool _placed = false;
  bool _placing = false;
  bool _surfaceFound = false;
  String? _trackingProblem;

  String? _sessionError;

  String get _hint {
    if (_sessionError != null) return _sessionError!;
    if (_placed) return 'Trascina per spostarla, ruota con due dita';
    if (_placing) return 'Caricamento della casetta…';
    if (_trackingProblem != null) return _trackingProblem!;
    if (_surfaceFound) {
      return 'Tocca un punto della superficie evidenziata per posizionarla';
    }
    return 'Inquadra il terreno e muovi lentamente il telefono';
  }

  static String? _describeTrackingFailure(String? reason) => switch (reason) {
    null || 'NONE' => null,
    'INSUFFICIENT_LIGHT' => 'Troppo buio: serve più luce',
    'EXCESSIVE_MOTION' => 'Muovi il telefono più lentamente',
    'INSUFFICIENT_FEATURES' =>
      'Inquadra una zona con più dettagli (erba, ghiaia, piastrelle…)',
    'CAMERA_UNAVAILABLE' => 'Fotocamera non disponibile',
    _ => 'Tracciamento perso, muovi lentamente il telefono',
  };

  /// [error] is the ARCore exception class name sent by the plugin.
  static String _describeSessionError(String error) => switch (error) {
    'UnavailableArcoreNotInstalledException' ||
    'UnavailableUserDeclinedInstallationException' =>
      'Installa "Google Play Services per AR" dal Play Store e riprova',
    'UnavailableApkTooOldException' =>
      'Aggiorna "Google Play Services per AR" dal Play Store e riprova',
    'UnavailableDeviceNotCompatibleException' =>
      'Questo telefono non supporta la realtà aumentata (ARCore)',
    'CameraNotAvailableException' =>
      'Fotocamera occupata da un\'altra app, chiudila e riprova',
    _ => 'Impossibile avviare la realtà aumentata ($error)',
  };

  @override
  void dispose() {
    _session?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        title: const Text('Nel tuo giardino'),
      ),
      body: FutureBuilder<PermissionStatus>(
        future: _camera,
        builder: (context, snap) {
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          if (!snap.data!.isGranted) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'Serve l\'accesso alla fotocamera per mostrare la casetta nel tuo giardino.',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                    FilledButton(
                      onPressed: openAppSettings,
                      child: const Text('Apri impostazioni'),
                    ),
                    const SizedBox(height: 8),
                    OutlinedButton(
                      onPressed: _usePhoto,
                      child: const Text('Usa una foto'),
                    ),
                  ],
                ),
              ),
            );
          }
          return Stack(
            children: [
              ARView(
                onARViewCreated: _onCreated,
                planeDetectionConfig: PlaneDetectionConfig.horizontal,
              ),
              Positioned(
                left: 16,
                right: 16,
                bottom: 32,
                child: SafeArea(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Flexible(
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 10,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.black54,
                            borderRadius: BorderRadius.circular(24),
                          ),
                          child: Text(
                            _hint,
                            style: const TextStyle(color: Colors.white),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ),
                      if (_sessionError != null) ...[
                        const SizedBox(width: 12),
                        FilledButton.icon(
                          onPressed: _usePhoto,
                          icon: const Icon(Icons.photo_outlined),
                          label: const Text('Usa una foto'),
                        ),
                      ],
                      if (_placed) ...[
                        const SizedBox(width: 12),
                        IconButton.filled(
                          tooltip: 'Rimuovi',
                          onPressed: _remove,
                          icon: const Icon(Icons.delete_outline),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  void _onCreated(
    ARSessionManager session,
    ARObjectManager objects,
    ARAnchorManager anchors,
    ARLocationManager location,
  ) {
    _session = session;
    _objects = objects;
    _anchors = anchors;
    session.onInitialize(
      showFeaturePoints: false,
      showPlanes: true,
      showWorldOrigin: false,
      handlePans: true,
      handleRotation: true,
    );
    objects.onInitialize();
    session.onPlaneOrPointTap = _onTap;
    session.onError = (error) {
      if (mounted) setState(() => _sessionError = _describeSessionError(error));
    };
    // Either event means the session is running (e.g. after ARCore was
    // installed), so any earlier start-up error no longer applies.
    session.onPlaneDetected = (_) {
      if (mounted && (!_surfaceFound || _sessionError != null)) {
        setState(() {
          _surfaceFound = true;
          _sessionError = null;
        });
      }
    };
    session.onTrackingFailure = (reason) {
      final problem = _describeTrackingFailure(reason);
      if (mounted && (problem != _trackingProblem || _sessionError != null)) {
        setState(() {
          _trackingProblem = problem;
          _sessionError = null;
        });
      }
    };
  }

  Future<void> _onTap(List<ARHitTestResult> hits) async {
    if (_placed || _placing) return;
    final hit = hits.where((h) => h.type == ARHitTestResultType.plane);
    if (hit.isEmpty) return;

    setState(() => _placing = true);
    ARPlaneAnchor? anchor;
    var anchorAdded = false;
    try {
      anchor = ARPlaneAnchor(transformation: hit.first.worldTransform);
      if (await _anchors!.addAnchor(anchor) != true) {
        _showError('Impossibile ancorare la casetta, riprova');
        return;
      }
      anchorAdded = true;

      final node = ARNode(
        type: NodeType.fileSystemAppFolderGLB,
        uri: 'file://${widget.glbPath}',
        // The plugin scales the model so its largest side measures this many meters.
        scale: Vector3.all(HouseModel.realSizeMeters),
        position: Vector3.zero(),
      );
      if (await _objects!.addNode(node, planeAnchor: anchor) == true) {
        _anchor = anchor;
        if (mounted) setState(() => _placed = true);
      } else {
        _anchors!.removeAnchor(anchor);
        _showError('Impossibile caricare il modello della casetta');
      }
    } catch (e) {
      debugPrint('Placing the house failed: $e');
      if (anchorAdded && _anchor == null) {
        try {
          _anchors?.removeAnchor(anchor!);
        } catch (_) {}
      }
      _showError('Impossibile posizionare la casetta, riprova');
    } finally {
      if (mounted) setState(() => _placing = false);
    }
  }

  void _usePhoto() => Navigator.of(context).pushReplacement(
    MaterialPageRoute(builder: (_) => PhotoScreen(model: widget.model)),
  );

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  void _remove() {
    final anchor = _anchor;
    if (anchor != null) _anchors!.removeAnchor(anchor);
    _anchor = null;
    setState(() => _placed = false);
  }
}
