import 'dart:io';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:share_plus/share_plus.dart';

import 'house_model.dart';
import 'house_viewer.dart';

/// "View it in your garden" for phones without ARCore: the user takes or
/// picks a photo of the garden and places the 3D house on it by hand.
class PhotoScreen extends StatefulWidget {
  const PhotoScreen({super.key, required this.model});
  final HouseModel model;

  @override
  State<PhotoScreen> createState() => _PhotoScreenState();
}

class _PhotoScreenState extends State<PhotoScreen> {
  /// Logical size of the square the house is rendered in, before [_scale].
  static const _houseBox = 280.0;

  final _viewer = HouseViewerController();
  File? _photo;

  // Placement, in logical pixels of the photo area.
  Offset? _center;
  double _scale = 1;
  double _theta = 35; // degrees around the house
  double _phi = 80; // camera height: 90 = eye level, smaller = from above

  // Gesture baselines.
  double _startScale = 1;
  double _startTheta = 0;

  bool _sharing = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _choosePhoto());
  }

  Future<void> _choosePhoto() async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const ListTile(
              title: Text(
                'Fotografa il punto del giardino dove vuoi la casetta',
              ),
            ),
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('Scatta una foto'),
              onTap: () => Navigator.pop(context, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Scegli dalla galleria'),
              onTap: () => Navigator.pop(context, ImageSource.gallery),
            ),
          ],
        ),
      ),
    );
    if (!mounted) return;
    if (source == null) {
      if (_photo == null && mounted) Navigator.pop(context);
      return;
    }
    // The app declares CAMERA (for AR), so Android refuses the camera intent
    // until the permission is granted.
    // On iOS image_picker asks for the permission itself.
    if (source == ImageSource.camera &&
        Platform.isAndroid &&
        !(await Permission.camera.request()).isGranted) {
      _showMessage('Serve l\'accesso alla fotocamera per scattare la foto');
      return;
    }
    if (!mounted) return;
    final XFile? picked;
    try {
      picked = await ImagePicker().pickImage(
        source: source,
        maxWidth: 2400,
        maxHeight: 2400,
        imageQuality: 90,
      );
    } on PlatformException catch (e) {
      debugPrint('pickImage failed: $e');
      _showMessage('Impossibile aprire la fotocamera o la galleria');
      return;
    }
    if (!mounted) return;
    if (picked == null) {
      if (_photo == null) Navigator.pop(context);
      return;
    }
    final path = picked.path;
    setState(() {
      _photo = File(path);
      _center = null; // re-centred on the next layout
    });
  }

  void _onScaleStart(ScaleStartDetails details) {
    _startScale = _scale;
    _startTheta = _theta;
  }

  void _onScaleUpdate(ScaleUpdateDetails details, Size area) {
    setState(() {
      final c = (_center ?? area.center(Offset.zero)) + details.focalPointDelta;
      _center = Offset(c.dx.clamp(0, area.width), c.dy.clamp(0, area.height));
      if (details.pointerCount > 1) {
        _scale = (_startScale * details.scale).clamp(0.2, 6.0);
        // Twisting two fingers turns the house around.
        _theta = _startTheta - details.rotation * 180 / pi;
        _viewer.setOrbit(_theta, _phi);
      }
    });
  }

  void _setPhi(double phi) {
    setState(() => _phi = phi);
    _viewer.setOrbit(_theta, _phi);
  }

  Future<void> _share(Size area) async {
    final photo = _photo;
    if (photo == null || _sharing) return;
    final pixelRatio = MediaQuery.devicePixelRatioOf(context);
    setState(() => _sharing = true);
    try {
      final house = await _viewer.snapshot();
      if (house == null) {
        _showMessage('La casetta non è ancora pronta, riprova tra un attimo');
        return;
      }
      final png = await _compose(
        photo: await photo.readAsBytes(),
        house: house,
        area: area,
        pixelRatio: pixelRatio,
      );
      final file = File(
        '${(await getTemporaryDirectory()).path}/casetta_giardino.png',
      );
      await file.writeAsBytes(png, flush: true);
      await SharePlus.instance.share(
        ShareParams(files: [XFile(file.path)], text: 'La mia Garden House'),
      );
    } catch (e) {
      debugPrint('Sharing the photo failed: $e');
      _showMessage('Condivisione non riuscita, riprova');
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  /// Draws exactly what's on screen (photo with BoxFit.cover, house on top)
  /// into a PNG.
  Future<Uint8List> _compose({
    required Uint8List photo,
    required Uint8List house,
    required Size area,
    required double pixelRatio,
  }) async {
    Future<ui.Image> decode(Uint8List bytes) async {
      final codec = await ui.instantiateImageCodec(bytes);
      return (await codec.getNextFrame()).image;
    }

    final photoImage = await decode(photo);
    final houseImage = await decode(house);
    final ratio = min(pixelRatio, 2400 / max(area.width, area.height));
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder)..scale(ratio);
    paintImage(
      canvas: canvas,
      rect: Offset.zero & area,
      image: photoImage,
      fit: BoxFit.cover,
      filterQuality: FilterQuality.high,
    );
    final size = _houseBox * _scale;
    paintImage(
      canvas: canvas,
      rect: Rect.fromCenter(
        center: _center ?? area.center(Offset.zero),
        width: size,
        height: size,
      ),
      image: houseImage,
      fit: BoxFit.fill,
      filterQuality: FilterQuality.high,
    );
    final image = await recorder.endRecording().toImage(
      (area.width * ratio).round(),
      (area.height * ratio).round(),
    );
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    photoImage.dispose();
    houseImage.dispose();
    image.dispose();
    return data!.buffer.asUint8List();
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final photo = _photo;
    return Scaffold(
      backgroundColor: Colors.black,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        title: const Text('Nel tuo giardino'),
        actions: [
          IconButton(
            tooltip: 'Cambia foto',
            onPressed: _choosePhoto,
            icon: const Icon(Icons.add_photo_alternate_outlined),
          ),
        ],
      ),
      body: photo == null
          ? const SizedBox.expand()
          : LayoutBuilder(
              builder: (context, constraints) {
                final area = constraints.biggest;
                final center = _center ?? area.center(Offset.zero);
                final size = _houseBox * _scale;
                return Stack(
                  children: [
                    Positioned.fill(
                      child: Image.file(photo, fit: BoxFit.cover),
                    ),
                    Positioned(
                      left: center.dx - _houseBox / 2,
                      top: center.dy - _houseBox / 2,
                      width: _houseBox,
                      height: _houseBox,
                      // A transform rather than a resize, so the WebView
                      // isn't re-laid out on every pinch frame.
                      child: Transform.scale(
                        scale: size / _houseBox,
                        child: HouseViewer(
                          model: widget.model,
                          controller: _viewer,
                          initialOrbit: '${_theta}deg ${_phi}deg auto',
                        ),
                      ),
                    ),
                    Positioned.fill(
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onScaleStart: _onScaleStart,
                        onScaleUpdate: (d) => _onScaleUpdate(d, area),
                      ),
                    ),
                    Positioned(
                      left: 16,
                      right: 16,
                      bottom: 16,
                      child: SafeArea(child: _controls(area)),
                    ),
                  ],
                );
              },
            ),
    );
  }

  Widget _controls(Size area) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
      decoration: BoxDecoration(
        color: Colors.black54,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'Trascina per spostarla, pizzica per ridimensionarla, '
            'ruota con due dita',
            style: TextStyle(color: Colors.white),
            textAlign: TextAlign.center,
          ),
          Row(
            children: [
              const Icon(Icons.height, color: Colors.white70),
              Expanded(
                child: Slider(
                  // Matches the camera height of the photo.
                  value: _phi,
                  min: 45,
                  max: 90,
                  onChanged: _setPhi,
                ),
              ),
              IconButton.filled(
                tooltip: 'Condividi',
                onPressed: _sharing ? null : () => _share(area),
                icon: _sharing
                    ? const SizedBox.square(
                        dimension: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.share),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
