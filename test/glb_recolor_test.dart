import 'dart:convert';
import 'dart:typed_data';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:garden_house_app/glb_recolor.dart';

Map<String, dynamic> jsonOf(Uint8List glb) {
  final d = ByteData.sublistView(glb);
  final len = d.getUint32(12, Endian.little);
  return jsonDecode(utf8.decode(glb.sublist(20, 20 + len)))
      as Map<String, dynamic>;
}

void main() {
  final src = File('assets/models/garden_house.glb').readAsBytesSync();

  test('recolors structure and panels, leaves the rest alone', () {
    final out = GlbRecolorer(src).build({
      HousePart.structure: const Paint(0xFF0000),
      HousePart.panels: const Paint(0x00FF00, metallic: 0.85, roughness: 0.35),
    });

    final j = jsonOf(out);
    final orig = jsonOf(src);
    final mats = (j['materials'] as List).cast<Map<String, dynamic>>();
    final origMats = (orig['materials'] as List).cast<Map<String, dynamic>>();
    expect(mats.length, origMats.length);

    Map<String, dynamic> named(String name) =>
        mats.singleWhere((m) => m['name'] == name);
    List<double> base(String name) =>
        ((named(name)['pbrMetallicRoughness']['baseColorFactor']) as List)
            .cast<num>()
            .map((e) => e.toDouble())
            .toList();

    expect(base(HousePart.structure.materialName), [1.0, 0.0, 0.0, 1.0]);
    expect(base(HousePart.panels.materialName)[1], 1.0);
    expect(
      named(HousePart.panels.materialName)['pbrMetallicRoughness']
          ['metallicFactor'],
      0.85,
    );

    // Everything else keeps its original material.
    for (var i = 0; i < mats.length; i++) {
      if (HousePart.values.any((p) => p.materialName == mats[i]['name'])) {
        continue;
      }
      expect(mats[i], origMats[i]);
    }

    // Valid container: length field matches, chunks 4-byte aligned, bin intact.
    expect(ByteData.sublistView(out).getUint32(8, Endian.little), out.length);
    expect(out.length % 4, 0);
    expect(GlbRecolorer(out).build({}).length, out.length);
  });

  test('optimized model stays light enough for phones', () {
    final j = jsonOf(src);
    final prims = [
      for (final m in j['meshes'] as List) ...(m['primitives'] as List),
    ];
    final accessors = j['accessors'] as List;
    final tris = prims.fold<int>(
      0,
      (sum, p) => sum + (accessors[p['indices']]['count'] as int) ~/ 3,
    );
    expect(prims.length, lessThan(20)); // draw calls
    expect(tris, lessThan(100000));
    expect(jsonEncode(j['materials']), isNot(contains('transmission')));
    // Quantized geometry (tools/optimize_glb.py); the float version is ~1.7
    // MB. The panels' texture coordinates add ~180 KB, their normal map ~40.
    expect(j['extensionsRequired'], contains('KHR_mesh_quantization'));
    expect(src.length, lessThan(1100 * 1024));
  });

  test('panels have texture coordinates for the finish textures', () {
    final j = jsonOf(src);
    final materials = j['materials'] as List;
    final panels = (j['meshes'][0]['primitives'] as List).singleWhere(
      (p) => materials[p['material']]['name'] == HousePart.panels.materialName,
    );
    expect((panels['attributes'] as Map).keys, contains('TEXCOORD_0'));
  });

  test('model has glass panes and real materials for the fixed parts', () {
    final j = jsonOf(src);
    final materials = (j['materials'] as List).cast<Map<String, dynamic>>();
    final names = materials.map((m) => m['name']).toSet();
    expect(names, containsAll(['glass', 'roof', 'lining', 'drain']));
    // No CAD placeholder colors left (the yellow roof, turquoise pipes).
    expect(names, isNot(anyOf(contains('Yellow'), contains('Turquoise'))));
    final glass = materials.singleWhere((m) => m['name'] == 'glass');
    expect(glass['alphaMode'], 'BLEND');
    final panels = (j['meshes'][0]['primitives'] as List).singleWhere(
      (p) => materials[p['material']]['name'] == HousePart.panels.materialName,
    );
    // Groove occlusion and the default embossing.
    expect((panels['attributes'] as Map).keys, contains('COLOR_0'));
    expect(
      materials.singleWhere(
        (m) => m['name'] == HousePart.panels.materialName,
      )['normalTexture'],
      isNotNull,
    );
  });

  test('embeds the texture of a textured paint', () {
    final recolorer = GlbRecolorer(src);
    final plain = recolorer.build({});
    final image = Uint8List.fromList(List.generate(1001, (i) => i % 256));
    final normals = Uint8List.fromList(List.generate(77, (i) => 255 - i));
    const paint = Paint(0x00FF00, texture: 'noce');
    final out = recolorer.build(
      {HousePart.structure: const Paint(0xFF0000), HousePart.panels: paint},
      images: {paint.textureAsset!: image, paint.normalAsset!: normals},
    );
    final j = jsonOf(out);
    final orig = jsonOf(src);
    final textures = j['textures'] as List;
    final images = j['images'] as List;
    // Appended after the model's own images and textures.
    expect(textures.length, (orig['textures'] as List).length + 2);
    expect(images.length, (orig['images'] as List).length + 2);
    expect(images.sublist(0, images.length - 2), orig['images']);
    expect(j['extensionsRequired'], orig['extensionsRequired']);

    final panels = (j['materials'] as List).singleWhere(
      (m) => m['name'] == HousePart.panels.materialName,
    )['pbrMetallicRoughness'];
    expect(panels['baseColorTexture'], {'index': textures.length - 2});
    final panelMaterial = (j['materials'] as List).singleWhere(
      (m) => m['name'] == HousePart.panels.materialName,
    );
    expect(panelMaterial['normalTexture'], {'index': textures.length - 1});
    expect(panels['baseColorFactor'], [1.0, 1.0, 1.0, 1.0]);
    final structure = (j['materials'] as List).singleWhere(
      (m) => m['name'] == HousePart.structure.materialName,
    )['pbrMetallicRoughness'];
    expect(structure.containsKey('baseColorTexture'), isFalse);

    final texture = textures[textures.length - 2];
    expect(texture['source'], images.length - 2);
    expect(j['samplers'][texture['sampler']]['wrapS'], 10497);

    // The image bytes are in the BIN chunk where the buffer view says.
    final d = ByteData.sublistView(out);
    final jsonLen = d.getUint32(12, Endian.little);
    final binStart = 20 + jsonLen + 8;
    final binLen = d.getUint32(20 + jsonLen, Endian.little);
    expect(binLen % 4, 0);
    expect(j['buffers'][0]['byteLength'], lessThanOrEqualTo(binLen));
    final view = j['bufferViews'][images[images.length - 2]['bufferView']];
    expect(view['byteOffset'] % 4, 0);
    final start = binStart + view['byteOffset'] as int;
    expect(out.sublist(start, start + image.length), image);
    expect(d.getUint32(8, Endian.little), out.length);

    // Untextured builds don't grow, and a missing image means flat color.
    expect(recolorer.build({}).length, plain.length);
    final missing = jsonOf(recolorer.build({HousePart.panels: paint}));
    expect(missing['textures'], orig['textures']);
    // Plain colors keep the model's own normal map (the panel embossing).
    expect(
      (missing['materials'] as List).singleWhere(
        (m) => m['name'] == HousePart.panels.materialName,
      )['normalTexture'],
      isNotNull,
    );
  });

  test('linearRgba converts sRGB to linear', () {
    expect(const Paint(0xFFFFFF).linearRgba, [1.0, 1.0, 1.0, 1.0]);
    expect(const Paint(0x000000).linearRgba, [0.0, 0.0, 0.0, 1.0]);
    expect(const Paint(0x808080).linearRgba[0], closeTo(0.2158, 1e-4));
  });
}
