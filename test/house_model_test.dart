import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:garden_house_app/glb_recolor.dart';
import 'package:garden_house_app/house_model.dart';
import 'package:garden_house_app/palette.dart';
import 'package:garden_house_app/share_config.dart';

void main() {
  HouseModel newModel() => HouseModel(
    GlbRecolorer(File('assets/models/garden_house.glb').readAsBytesSync()),
    Directory.systemTemp,
  );

  test('undo steps back through changes', () {
    final model = newModel();
    final initial = Map.of(model.paints);
    expect(model.canUndo, isFalse);

    model.setColor(HousePart.structure, 0x178048);
    model.setFinish(HousePart.panels, Finish.gloss);
    model.setColor(HousePart.structure, 0x178048); // no change, no step
    expect(model.paints[HousePart.panels]!.finish, Finish.gloss);

    model.undo();
    expect(model.paints[HousePart.panels], initial[HousePart.panels]);
    expect(model.paints[HousePart.structure]!.color, 0x178048);
    model.undo();
    expect(model.paints, initial);
    expect(model.canUndo, isFalse);
    model.dispose();
  });

  test('applying a combo is a single undo step', () {
    final model = newModel();
    final initial = Map.of(model.paints);
    final combo = combos.firstWhere((c) => !c.matches(initial));
    model.applyConfig(combo.config);
    expect(combo.matches(model.paints), isTrue);
    model.undo();
    expect(model.paints, initial);
    model.dispose();
  });

  test('configs round-trip through JSON', () {
    final config = {
      HousePart.structure: const Paint(
        0x123456,
        metallic: 0.85,
        roughness: 0.35,
      ),
      HousePart.panels: const Paint(0xABCDEF),
    };
    expect(configFromJson(configToJson(config)), config);
    final textured = {
      HousePart.panels: const Paint(0xE9E4DB, texture: 'doga-goffrato-ral9010'),
    };
    expect(configFromJson(configToJson(textured)), textured);
    // Saved before textures existed.
    expect(
      configFromJson({
        'panels': {'color': 0xABCDEF, 'metallic': 0, 'roughness': 0.7},
      }),
      {HousePart.panels: const Paint(0xABCDEF)},
    );
    // Unknown or missing parts are ignored rather than failing.
    expect(configFromJson({'roof': {}}), isEmpty);
  });

  test('random configs keep the parts distinguishable', () {
    final random = Random(1);
    for (var i = 0; i < 200; i++) {
      final c = randomConfig(random);
      final a = Paint(c[HousePart.structure]!.color);
      final b = Paint(c[HousePart.panels]!.color);
      double lum(Paint p) =>
          0.2126 * p.linearRgba[0] +
          0.7152 * p.linearRgba[1] +
          0.0722 * p.linearRgba[2];
      final ratio = (max(lum(a), lum(b)) + 0.05) / (min(lum(a), lum(b)) + 0.05);
      expect(ratio, greaterThanOrEqualTo(1.8));
    }
  });

  test('panel finishes are undoable and named', () async {
    final model = HouseModel(
      GlbRecolorer(File('assets/models/garden_house.glb').readAsBytesSync()),
      Directory.systemTemp,
      null,
      (key) => File(key).readAsBytes(),
    );
    final finish = panelFinishes[1];
    model.setFinish(HousePart.panels, Finish.satin);
    model.setTexture(HousePart.panels, finish.id, finish.rgb);
    expect(model.paints[HousePart.panels]!.texture, finish.id);
    expect(model.paints[HousePart.panels]!.finish, Finish.satin);
    expect(
      describeConfig({HousePart.panels: model.paints[HousePart.panels]!}),
      'Pannelli: Doga centrale goffrato RAL 9010 (#E9E4DB), Satinato',
    );

    // Every finish has its texture and thumbnail.
    for (final f in panelFinishes) {
      expect(File('assets/textures/${f.id}.jpg').existsSync(), isTrue);
      expect(File(f.thumbnail).existsSync(), isTrue);
    }

    final path = await model.exportGlb();
    final glb = File(path).readAsBytesSync();
    final jsonLen = ByteData.sublistView(glb).getUint32(12, Endian.little);
    final json = utf8.decode(glb.sublist(20, 20 + jsonLen));
    expect(json, contains('"baseColorTexture"'));
    expect(json, contains('image/jpeg'));
    await File(path).delete();

    model.setColor(HousePart.panels, 0x178048);
    expect(model.paints[HousePart.panels]!.texture, isNull);
    model.undo();
    expect(model.paints[HousePart.panels]!.texture, finish.id);
    model.undo();
    expect(model.paints[HousePart.panels]!.texture, isNull);
    model.dispose();
  });

  test('describeConfig names presets and shows hex codes', () {
    final text = describeConfig({
      HousePart.structure: const Paint(0x8B4513).withFinish(Finish.satin),
      HousePart.panels: const Paint(0x010203),
    });
    expect(text, 'Struttura: Marrone (#8B4513), Satinato\nPannelli: #010203');
  });
}
