import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'glb_recolor.dart';
import 'house_model.dart';

/// Named presets. The first nine of each list are the colors offered on the
/// website's configurator; the rest are additions.
class Swatch {
  const Swatch(this.name, this.rgb);
  final String name;
  final int rgb;
  Color get color => Color(0xFF000000 | rgb);
}

const structureSwatches = <Swatch>[
  Swatch('Marrone', 0x8B4513),
  Swatch('Verde', 0x178048),
  Swatch('Grigio chiaro', 0x9DA6A1),
  Swatch('Ocra', 0xF4A300),
  Swatch('Bianco', 0xF5F5F5),
  Swatch('Antracite', 0x2F4F4F),
  Swatch('Lilla', 0xCFABD6),
  Swatch('Rosso', 0xDB2612),
  Swatch('Azzurro', 0x12C0E3),
  Swatch('Nero', 0x1A1A1A),
  Swatch('Grigio grafite', 0x474A4F),
  Swatch('Grigio perla', 0xC9CCCF),
  Swatch('Avorio', 0xF2EBD3),
  Swatch('Sabbia', 0xD8C3A0),
  Swatch('Tortora', 0x8B7D6B),
  Swatch('Noce', 0x5C4033),
  Swatch('Verde bosco', 0x2F5233),
  Swatch('Verde salvia', 0x9CAF88),
  Swatch('Verde oliva', 0x6B7A3A),
  Swatch('Blu notte', 0x1F2D4D),
  Swatch('Blu petrolio', 0x1F5F6B),
  Swatch('Bordeaux', 0x6D1F2B),
  Swatch('Arancio', 0xE0752B),
  Swatch('Giallo', 0xF2D024),
];

const panelSwatches = <Swatch>[
  ...structureSwatches,
  Swatch('Rosa antico', 0xC98E94),
  Swatch('Turchese', 0x2AA198),
  Swatch('Terracotta', 0xB8573A),
  Swatch('Menta', 0xB5E0CC),
];

/// One of the 16 panel finishes of the Techs Garden House brochure: a texture
/// made from the brochure's panel photo (tools/make_textures.py) and its
/// average color.
class PanelFinish {
  const PanelFinish(this.id, this.name, this.rgb);

  /// Texture id: `assets/textures/<id>.jpg`, `assets/finiture/<id>.webp`.
  final String id;
  final String name;
  final int rgb;
  Color get color => Color(0xFF000000 | rgb);

  /// The brochure's photo of the panel, for the picker.
  String get thumbnail => 'assets/finiture/$id.webp';
}

/// In the brochure's order. "Doga centrale" boards have a central groove,
/// "piano" boards are plain (the 3D model always shows the groove).
const panelFinishes = <PanelFinish>[
  PanelFinish('piano-goffrato-ral9010', 'Piano goffrato RAL 9010', 0xF0ECE2),
  PanelFinish(
    'doga-goffrato-ral9010',
    'Doga centrale goffrato RAL 9010',
    0xE9E4DB,
  ),
  PanelFinish('doga-liscio-ral9010', 'Doga centrale liscio RAL 9010', 0xF2EEE4),
  PanelFinish('doga-liscio-ral1013', 'Doga centrale liscio RAL 1013', 0xE1D8C2),
  PanelFinish('doga-liscio-ral7035', 'Doga centrale liscio RAL 7035', 0xC4CDCA),
  PanelFinish('doga-liscio-ral9006', 'Doga centrale liscio RAL 9006', 0xA09D9C),
  PanelFinish('piano-liscio-ral9006', 'Piano liscio RAL 9006', 0xA09D9C),
  PanelFinish(
    'doga-polygrain-ral7016',
    'Doga centrale polygrain RAL 7016',
    0x3C3D3B,
  ),
  PanelFinish('piano-polygrain-ral7016', 'Piano polygrain RAL 7016', 0x3C3D3B),
  PanelFinish(
    'doga-goffrato-ral6005',
    'Doga centrale goffrato RAL 6005',
    0x1A4539,
  ),
  PanelFinish(
    'doga-goffrato-ral6009',
    'Doga centrale goffrato RAL 6009',
    0x183020,
  ),
  PanelFinish('piano-liscio-noce-chiaro', 'Piano liscio Noce chiaro', 0x6D4324),
  PanelFinish(
    'doga-liscio-noce-chiaro',
    'Doga centrale liscio Noce chiaro',
    0x6E4325,
  ),
  PanelFinish('piano-liscio-noce-scuro', 'Piano liscio Noce scuro', 0x573F27),
  PanelFinish(
    'doga-liscio-noce-scuro',
    'Doga centrale liscio Noce scuro',
    0x4C351F,
  ),
  PanelFinish(
    'doga-goffrato-ral8014',
    'Doga centrale goffrato RAL 8014',
    0x302214,
  ),
];

PanelFinish? panelFinishById(String? id) =>
    panelFinishes.where((f) => f.id == id).firstOrNull;

/// Name of the preset with color [rgb], if there is one.
String? swatchName(int rgb) =>
    panelSwatches.where((s) => s.rgb == rgb).firstOrNull?.name;

/// Name of [paint]'s panel finish or color preset, if it has one.
String? paintName(Paint paint) =>
    panelFinishById(paint.texture)?.name ?? swatchName(paint.color);

/// A ready-made structure + panels pairing.
class Combo {
  const Combo(
    this.name,
    this.structure,
    this.panels, {
    this.structureFinish = Finish.satin,
    this.panelFinish = Finish.matte,
  });

  final String name;
  final int structure;
  final int panels;
  final Finish structureFinish;
  final Finish panelFinish;

  HouseConfig get config => {
    HousePart.structure: Paint(structure).withFinish(structureFinish),
    HousePart.panels: Paint(panels).withFinish(panelFinish),
  };

  /// Whether [config] is exactly this combo.
  bool matches(HouseConfig config) => mapEquals(config, this.config);
}

const combos = <Combo>[
  Combo('Classica', 0x8B4513, 0xF5F5F5),
  Combo('Scandinava', 0xF5F5F5, 0x9DA6A1),
  Combo('Bosco', 0x5C4033, 0x2F5233),
  Combo('Provenzale', 0xF2EBD3, 0x9CAF88),
  Combo('Moderna', 0x2F4F4F, 0xC9CCCF, structureFinish: Finish.metal),
  Combo('Mediterranea', 0xF5F5F5, 0x1F5F6B),
  Combo('Toscana', 0x5C4033, 0xB8573A),
  Combo('Nordica', 0x1A1A1A, 0xD8C3A0, panelFinish: Finish.satin),
  Combo('Giardino inglese', 0x2F5233, 0xF2EBD3),
  Combo('Pop', 0xF5F5F5, 0xDB2612, panelFinish: Finish.gloss),
];

/// A random structure/panels pair from the presets with enough contrast
/// between the two to tell the parts apart.
HouseConfig randomConfig([Random? random]) {
  random ??= Random();
  final finishes = [Finish.matte, Finish.satin, Finish.satin, Finish.gloss];
  while (true) {
    final structure =
        structureSwatches[random.nextInt(structureSwatches.length)];
    final panels = panelSwatches[random.nextInt(panelSwatches.length)];
    final a = structure.color.computeLuminance();
    final b = panels.color.computeLuminance();
    if ((max(a, b) + 0.05) / (min(a, b) + 0.05) < 1.8) continue;
    return {
      HousePart.structure: Paint(structure.rgb)
          .withFinish(finishes[random.nextInt(finishes.length)]),
      HousePart.panels: Paint(panels.rgb)
          .withFinish(finishes[random.nextInt(finishes.length)]),
    };
  }
}
