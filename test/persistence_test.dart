import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:garden_house_app/glb_recolor.dart';
import 'package:garden_house_app/house_model.dart';
import 'package:garden_house_app/local_store.dart';
import 'package:garden_house_app/saved_configs.dart';

void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('garden_house_'));
  tearDown(() => dir.deleteSync(recursive: true));

  File settings() => File('${dir.path}/settings.json');

  group('LocalStore', () {
    test('starts empty and persists what is set', () async {
      final store = await LocalStore.open(settings());
      expect(store.getString('a'), isNull);
      await store.setString('a', '1');
      await store.setString('b', '2');
      expect(store.getString('a'), '1');

      final reopened = await LocalStore.open(settings());
      expect(reopened.getString('a'), '1');
      expect(reopened.getString('b'), '2');
      expect(File('${settings().path}.tmp').existsSync(), isFalse);
    });

    test('serialized writes keep the last value', () async {
      final store = await LocalStore.open(settings());
      await Future.wait([
        for (var i = 0; i < 20; i++) store.setString('n', '$i'),
      ]);
      expect((await LocalStore.open(settings())).getString('n'), '19');
    });

    test('moves a corrupt file aside instead of overwriting it', () async {
      settings().writeAsStringSync('{"last_config": "{"');
      final store = await LocalStore.open(settings());
      expect(store.getString('last_config'), isNull);
      expect(File('${settings().path}.bad').readAsStringSync(), isNotEmpty);

      await store.setString('a', '1');
      expect((await LocalStore.open(settings())).getString('a'), '1');
    });

    test('a value that is not a string reads as null', () async {
      settings().writeAsStringSync('{"a": 1, "b": "x"}');
      final store = await LocalStore.open(settings());
      expect(store.getString('a'), isNull);
      expect(store.getString('b'), 'x');
    });
  });

  group('SavedConfigs', () {
    const a = SavedConfig('A', {
      HousePart.structure: Paint(0x8B4513, roughness: 0.5),
      HousePart.panels: Paint(0xE9E4DB, texture: 'doga-goffrato-ral9010'),
    });
    const b = SavedConfig('B', {HousePart.panels: Paint(0x123456)});

    test('round-trip', () {
      final decoded = SavedConfigs.decode(SavedConfigs.encode([a, b]));
      expect(decoded.map((c) => c.name), ['A', 'B']);
      expect(decoded[0].config, a.config);
      expect(decoded[1].config, b.config);
    });

    test('a bad entry does not lose the others', () {
      final raw = jsonEncode([
        a.toJson(),
        {'name': 'no paints'},
        {
          'name': 'bad paint',
          'paints': {
            'panels': {'color': 'red'},
          },
        },
        42,
        b.toJson(),
      ]);
      expect(SavedConfigs.decode(raw).map((c) => c.name), ['A', 'B']);
    });

    test('unreadable data is an empty list', () {
      expect(SavedConfigs.decode(null), isEmpty);
      expect(SavedConfigs.decode('not json'), isEmpty);
      expect(SavedConfigs.decode('{"name": "A"}'), isEmpty);
    });
  });

  test('configFromJson skips a malformed part, keeps the rest', () {
    expect(
      configFromJson({
        'structure': {'color': 0x010203, 'metallic': 0, 'roughness': 0.5},
        'panels': {'color': 'white'},
      }),
      {HousePart.structure: const Paint(0x010203, roughness: 0.5)},
    );
  });

  group('HouseModel', () {
    final glb = File('assets/models/garden_house.glb').readAsBytesSync();

    test('saves the last change even when disposed right after it', () async {
      final store = await LocalStore.open(settings());
      final model = HouseModel(GlbRecolorer(glb), dir, store);
      model.setColor(HousePart.structure, 0x178048);
      model.dispose();
      // Writes are serialized, so this one completes after the flush.
      await store.setString('marker', '');

      final saved = (await LocalStore.open(settings()))
          .getString('last_config');
      expect(
        configFromJson(
          jsonDecode(saved!) as Map<String, dynamic>,
        )[HousePart.structure]!.color,
        0x178048,
      );
    });

    test('flush saves only when a change is pending', () async {
      final store = await LocalStore.open(settings());
      final model = HouseModel(GlbRecolorer(glb), dir, store);
      await model.flush();
      expect(store.getString('last_config'), isNull);
      model.setFinish(HousePart.panels, Finish.gloss);
      await model.flush();
      expect(store.getString('last_config'), contains('0.15'));
      model.dispose();
    });

    test('exports a flat color when a texture asset is missing', () async {
      final model = HouseModel(
        GlbRecolorer(glb),
        dir,
        null,
        (key) async => throw StateError('No asset $key'),
      );
      model.setTexture(HousePart.panels, 'discontinued-finish', 0x123456);
      final path = await model.exportGlb();
      final out = File(path).readAsBytesSync();
      final jsonLen = ByteData.sublistView(out).getUint32(12, Endian.little);
      final json = jsonDecode(
        utf8.decode(out.sublist(20, 20 + jsonLen)),
      ) as Map<String, dynamic>;
      final panels = (json['materials'] as List).singleWhere(
        (m) => m['name'] == HousePart.panels.materialName,
      );
      expect(panels['pbrMetallicRoughness']['baseColorTexture'], isNull);
      expect(
        panels['pbrMetallicRoughness']['baseColorFactor'],
        const Paint(0x123456).linearRgba,
      );
      model.dispose();
    });
  });
}
