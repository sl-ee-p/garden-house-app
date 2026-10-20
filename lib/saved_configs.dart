import 'dart:convert';

import 'package:flutter/material.dart';

import 'glb_recolor.dart';
import 'house_model.dart';
import 'local_store.dart';

/// A configuration the user saved under a name.
class SavedConfig {
  const SavedConfig(this.name, this.config);

  factory SavedConfig.fromJson(Map<String, dynamic> json) => SavedConfig(
    json['name'] as String,
    configFromJson(json['paints'] as Map<String, dynamic>),
  );

  final String name;
  final HouseConfig config;

  Map<String, dynamic> toJson() => {
    'name': name,
    'paints': configToJson(config),
  };
}

/// Favorites, newest first, kept in the [LocalStore].
class SavedConfigs {
  static const _key = 'saved_configs';

  static Future<List<SavedConfig>> load() async {
    final raw = (await LocalStore.instance).getString(_key);
    if (raw == null) return [];
    try {
      return [
        for (final e in jsonDecode(raw) as List)
          SavedConfig.fromJson(e as Map<String, dynamic>),
      ];
    } on Object catch (e) {
      debugPrint('Ignoring saved configurations: $e');
      return [];
    }
  }

  static Future<void> store(List<SavedConfig> configs) async =>
      (await LocalStore.instance).setString(
        _key,
        jsonEncode([for (final c in configs) c.toJson()]),
      );
}

/// Bottom sheet listing the favorites: tap applies one, swipe deletes it,
/// and the button saves the current configuration.
Future<void> showSavedConfigs(BuildContext context, HouseModel model) =>
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => _SavedConfigsSheet(model: model),
    );

class _SavedConfigsSheet extends StatefulWidget {
  const _SavedConfigsSheet({required this.model});
  final HouseModel model;

  @override
  State<_SavedConfigsSheet> createState() => _SavedConfigsSheetState();
}

class _SavedConfigsSheetState extends State<_SavedConfigsSheet> {
  List<SavedConfig>? _configs;

  @override
  void initState() {
    super.initState();
    SavedConfigs.load().then((c) {
      if (mounted) setState(() => _configs = c);
    });
  }

  Future<void> _update(List<SavedConfig> configs) async {
    setState(() => _configs = configs);
    await SavedConfigs.store(configs);
  }

  Future<void> _saveCurrent() async {
    final configs = _configs;
    if (configs == null) return;
    final name = await showDialog<String>(
      context: context,
      builder: (_) =>
          _NameDialog(initial: 'La mia casetta ${configs.length + 1}'),
    );
    if (name == null || name.trim().isEmpty) return;
    await _update([
      SavedConfig(name.trim(), Map.of(widget.model.paints)),
      ...configs,
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final configs = _configs;
    final textTheme = Theme.of(context).textTheme;
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.7,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
              child: Text(
                'Configurazioni salvate',
                style: textTheme.titleLarge,
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: FilledButton.icon(
                onPressed: configs == null ? null : _saveCurrent,
                icon: const Icon(Icons.bookmark_add_outlined),
                label: const Text('Salva la configurazione attuale'),
              ),
            ),
            const SizedBox(height: 8),
            if (configs == null)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (configs.isEmpty)
              Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'Nessuna configurazione salvata. Salva quelle che ti piacciono '
                  'per confrontarle o ritrovarle più tardi.',
                  textAlign: TextAlign.center,
                  style: textTheme.bodyMedium,
                ),
              )
            else
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    for (final c in configs)
                      Dismissible(
                        key: ObjectKey(c),
                        direction: DismissDirection.endToStart,
                        background: Container(
                          color: Theme.of(context).colorScheme.errorContainer,
                          alignment: Alignment.centerRight,
                          padding: const EdgeInsets.only(right: 24),
                          child: const Icon(Icons.delete_outline),
                        ),
                        onDismissed: (_) => _update([...configs]..remove(c)),
                        child: ListTile(
                          leading: ConfigSwatch(config: c.config),
                          title: Text(c.name),
                          subtitle: const Text('Tocca per applicare'),
                          onTap: () {
                            widget.model.applyConfig(c.config);
                            Navigator.pop(context);
                          },
                        ),
                      ),
                  ],
                ),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

class _NameDialog extends StatefulWidget {
  const _NameDialog({required this.initial});
  final String initial;

  @override
  State<_NameDialog> createState() => _NameDialogState();
}

class _NameDialogState extends State<_NameDialog> {
  late final _text = TextEditingController(text: widget.initial)
    ..selection = TextSelection(
      baseOffset: 0,
      extentOffset: widget.initial.length,
    );

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Nome della configurazione'),
    content: TextField(
      controller: _text,
      autofocus: true,
      textCapitalization: TextCapitalization.sentences,
      onSubmitted: (v) => Navigator.pop(context, v),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Annulla'),
      ),
      FilledButton(
        onPressed: () => Navigator.pop(context, _text.text),
        child: const Text('Salva'),
      ),
    ],
  );
}

/// Circle split between the structure and panel colors.
class ConfigSwatch extends StatelessWidget {
  const ConfigSwatch({super.key, required this.config, this.size = 40});
  final HouseConfig config;
  final double size;

  @override
  Widget build(BuildContext context) {
    Color of(HousePart part) =>
        Color(0xFF000000 | (config[part]?.color ?? 0x808080));
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          stops: const [0.5, 0.5],
          colors: [of(HousePart.structure), of(HousePart.panels)],
        ),
      ),
    );
  }
}
