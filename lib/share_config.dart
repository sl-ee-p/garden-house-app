import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import 'contact.dart';
import 'glb_recolor.dart';
import 'house_model.dart';
import 'palette.dart';

const _partLabels = {
  HousePart.structure: 'Struttura',
  HousePart.panels: 'Pannelli',
};

/// Human-readable configuration, e.g. "Struttura: Marrone (#8B4513), Satinato".
String describeConfig(HouseConfig config) => [
  for (final MapEntry(key: part, value: paint) in config.entries)
    '${_partLabels[part]}: ${_describePaint(paint)}',
].join('\n');

String _describePaint(Paint paint) {
  final hex = '#${paint.color.toRadixString(16).padLeft(6, '0').toUpperCase()}';
  final name = paintName(paint);
  return [
    name == null ? hex : '$name ($hex)',
    ?paint.finish?.label,
  ].join(', ');
}

Future<XFile?> _renderFile(Uint8List? png) async {
  if (png == null) return null;
  final file = File('${(await getTemporaryDirectory()).path}/la_mia_garden_house.png');
  await file.writeAsBytes(png, flush: true);
  return XFile(file.path, mimeType: 'image/png');
}

/// Shares the render [png] (if any) with the configuration as text.
Future<void> shareConfig(HouseConfig config, Uint8List? png) async {
  final file = await _renderFile(png);
  await SharePlus.instance.share(
    ShareParams(
      text: 'La mia Garden House\n${describeConfig(config)}',
      files: [?file],
    ),
  );
}

/// Asks the seller for a quote: WhatsApp or email when configured in
/// contact.dart, the share sheet otherwise.
Future<void> requestQuote(
  BuildContext context,
  HouseConfig config,
  Uint8List? png,
) async {
  final text =
      'Buongiorno, vorrei un preventivo per una Garden House così '
      'configurata:\n${describeConfig(config)}';
  final options = <(String, IconData, Uri)>[
    if (quoteWhatsApp.isNotEmpty)
      (
        'WhatsApp',
        Icons.chat_outlined,
        Uri.https('wa.me', '/$quoteWhatsApp', {'text': text}),
      ),
    if (quoteEmail.isNotEmpty)
      (
        'Email',
        Icons.mail_outline,
        Uri(
          scheme: 'mailto',
          path: quoteEmail,
          // Not queryParameters: that encodes spaces as '+', which mail
          // apps show literally.
          query: 'subject=${Uri.encodeComponent('Richiesta preventivo Garden House')}'
              '&body=${Uri.encodeComponent(text)}',
        ),
      ),
  ];

  if (options.isEmpty) {
    final file = await _renderFile(png);
    await SharePlus.instance.share(
      ShareParams(text: text, subject: 'Richiesta preventivo', files: [?file]),
    );
    return;
  }
  final uri = options.length == 1
      ? options.single.$3
      : await showModalBottomSheet<Uri>(
          context: context,
          builder: (context) => SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const ListTile(title: Text('Come vuoi inviare la richiesta?')),
                for (final (label, icon, uri) in options)
                  ListTile(
                    leading: Icon(icon),
                    title: Text(label),
                    onTap: () => Navigator.pop(context, uri),
                  ),
              ],
            ),
          ),
        );
  if (uri != null && !await launchUrl(uri, mode: LaunchMode.externalApplication)) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Nessuna app disponibile per inviare la richiesta')),
      );
    }
  }
}
