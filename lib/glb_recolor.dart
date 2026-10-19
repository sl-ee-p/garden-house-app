import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

/// Which part of the garden house a color applies to.
enum HousePart {
  structure('paint-structure'),
  panels('paint-panels');

  const HousePart(this.materialName);

  /// Name of the material that tools/optimize_glb.py gives this part.
  final String materialName;
}

/// A surface look: base color plus PBR metalness/roughness, optionally with
/// one of the brochure's panel finish textures.
class Paint {
  const Paint(
    this.color, {
    this.metallic = 0,
    this.roughness = 0.7,
    this.texture,
  });

  /// 0xRRGGBB. With a [texture], the finish's average color, shown wherever
  /// the texture isn't (swatches, share text, while it loads).
  final int color;
  final double metallic;
  final double roughness;

  /// Id of a panel finish (`PanelFinish.id`), i.e. the image
  /// `assets/textures/<texture>.jpg`, or null for a plain color.
  final String? texture;

  /// Asset key of the [texture] image.
  String? get textureAsset =>
      texture == null ? null : 'assets/textures/$texture.jpg';

  factory Paint.fromJson(Map<String, dynamic> json) => Paint(
    json['color'] as int,
    metallic: (json['metallic'] as num).toDouble(),
    roughness: (json['roughness'] as num).toDouble(),
    // Absent in configurations saved before textures existed.
    texture: json['texture'] as String?,
  );

  Map<String, dynamic> toJson() => {
    'color': color,
    'metallic': metallic,
    'roughness': roughness,
    'texture': ?texture,
  };

  /// The preset finish this paint uses, if any.
  Finish? get finish => Finish.values
      .where((f) => f.metallic == metallic && f.roughness == roughness)
      .firstOrNull;

  /// A plain color: drops any texture.
  Paint withColor(int c) => Paint(c, metallic: metallic, roughness: roughness);
  Paint withFinish(Finish f) => Paint(
    color,
    metallic: f.metallic,
    roughness: f.roughness,
    texture: texture,
  );

  /// The texture [id], with [fallbackColor] as its color.
  Paint withTexture(String id, int fallbackColor) => Paint(
    fallbackColor,
    metallic: metallic,
    roughness: roughness,
    texture: id,
  );

  /// glTF baseColorFactor: linear RGBA (picker colors are sRGB).
  List<double> get linearRgba => [
    _linear((color >> 16) & 0xFF),
    _linear((color >> 8) & 0xFF),
    _linear(color & 0xFF),
    1.0,
  ];

  static double _linear(int channel) {
    final c = channel / 255;
    return c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4).toDouble();
  }

  @override
  bool operator ==(Object other) =>
      other is Paint &&
      other.color == color &&
      other.metallic == metallic &&
      other.roughness == roughness &&
      other.texture == texture;

  @override
  int get hashCode => Object.hash(color, metallic, roughness, texture);
}

enum Finish {
  matte('Opaco', 0, 0.9),
  satin('Satinato', 0, 0.5),
  gloss('Lucido', 0, 0.15),
  metal('Metallico', 0.85, 0.35);

  const Finish(this.label, this.metallic, this.roughness);
  final String label;
  final double metallic;
  final double roughness;
}

/// Rewrites the part materials of the garden house GLB so structure and
/// panels get the chosen paints. Edits the glTF JSON chunk; the binary chunk
/// (geometry, textures) is copied untouched, and only grows by the images of
/// textured paints.
class GlbRecolorer {
  GlbRecolorer(Uint8List glb) {
    final data = ByteData.sublistView(glb);
    if (data.getUint32(0, Endian.little) != _magic) {
      throw const FormatException('Not a GLB file');
    }
    var offset = 12;
    while (offset < glb.length) {
      final length = data.getUint32(offset, Endian.little);
      final type = data.getUint32(offset + 4, Endian.little);
      final body = Uint8List.sublistView(glb, offset + 8, offset + 8 + length);
      if (type == _jsonChunk) {
        _json = jsonDecode(utf8.decode(body)) as Map<String, dynamic>;
      } else if (type == _binChunk) {
        _bin = body;
      }
      offset += 8 + length;
    }
    if (_json == null) throw const FormatException('GLB has no JSON chunk');
    final names = [
      for (final m in (_json!['materials'] as List)) (m as Map)['name'],
    ];
    for (final part in HousePart.values) {
      if (!names.contains(part.materialName)) {
        throw FormatException('GLB has no "${part.materialName}" material');
      }
    }
  }

  static const _magic = 0x46546C67; // 'glTF'
  static const _jsonChunk = 0x4E4F534A;
  static const _binChunk = 0x004E4942;

  Map<String, dynamic>? _json;
  Uint8List? _bin;

  /// Returns a new GLB with [paints] applied. [textures] maps texture ids to
  /// JPEG bytes; a textured paint whose image is missing gets its flat color.
  Uint8List build(
    Map<HousePart, Paint> paints, {
    Map<String, Uint8List> textures = const {},
  }) {
    // Deep copy so the recolorer can be reused for many builds.
    final json = jsonDecode(jsonEncode(_json)) as Map<String, dynamic>;
    final materials = (json['materials'] as List).cast<Map<String, dynamic>>();
    final bin = BytesBuilder(copy: false)..add(_bin ?? Uint8List(0));
    final textureIndex = <String, int>{};
    for (final entry in paints.entries) {
      final paint = entry.value;
      final image = textures[paint.texture];
      final index = image == null
          ? null
          : textureIndex[paint.texture!] ??= _addTexture(json, bin, image);
      for (final m in materials) {
        if (m['name'] != entry.key.materialName) continue;
        m['pbrMetallicRoughness'] = {
          'baseColorFactor': index == null ? paint.linearRgba : [1.0, 1.0, 1.0, 1.0],
          'baseColorTexture': ?(index == null ? null : {'index': index}),
          'metallicFactor': paint.metallic,
          'roughnessFactor': paint.roughness,
        };
      }
    }
    if (textureIndex.isEmpty) return _pack(json, _bin);
    final out = bin.takeBytes();
    (json['buffers'] as List)[0]['byteLength'] = out.length;
    return _pack(json, out);
  }

  /// Appends the JPEG [image] to [bin] and to the glTF image, sampler and
  /// texture lists; returns the new texture's index.
  static int _addTexture(
    Map<String, dynamic> json,
    BytesBuilder bin,
    Uint8List image,
  ) {
    while (bin.length % 4 != 0) {
      bin.addByte(0);
    }
    List list(String key) => json[key] ??= [];
    list('bufferViews').add({
      'buffer': 0,
      'byteOffset': bin.length,
      'byteLength': image.length,
    });
    bin.add(image);
    list('images').add({
      'bufferView': list('bufferViews').length - 1,
      'mimeType': 'image/jpeg',
    });
    // REPEAT: the textures are pre-mirrored tiles (tools/make_textures.py).
    list('samplers').add({
      'magFilter': 9729, // LINEAR
      'minFilter': 9987, // LINEAR_MIPMAP_LINEAR
      'wrapS': 10497,
      'wrapT': 10497,
    });
    list('textures').add({
      'source': list('images').length - 1,
      'sampler': list('samplers').length - 1,
    });
    return list('textures').length - 1;
  }

  Uint8List _pack(Map<String, dynamic> json, Uint8List? bin) {
    var jsonBytes = utf8.encode(jsonEncode(json));
    final jsonPad = (4 - jsonBytes.length % 4) % 4;
    jsonBytes = Uint8List.fromList([
      ...jsonBytes,
      ...List.filled(jsonPad, 0x20),
    ]);
    final binLen = bin?.length ?? 0;
    final binPad = (4 - binLen % 4) % 4;
    final total =
        12 + 8 + jsonBytes.length + (bin == null ? 0 : 8 + binLen + binPad);

    final out = Uint8List(total);
    final d = ByteData.sublistView(out);
    d.setUint32(0, _magic, Endian.little);
    d.setUint32(4, 2, Endian.little);
    d.setUint32(8, total, Endian.little);
    d.setUint32(12, jsonBytes.length, Endian.little);
    d.setUint32(16, _jsonChunk, Endian.little);
    out.setRange(20, 20 + jsonBytes.length, jsonBytes);
    if (bin != null) {
      final at = 20 + jsonBytes.length;
      d.setUint32(at, binLen + binPad, Endian.little);
      d.setUint32(at + 4, _binChunk, Endian.little);
      out.setRange(at + 8, at + 8 + binLen, bin);
    }
    return out;
  }
}
