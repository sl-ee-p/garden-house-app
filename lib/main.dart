import 'package:ar_flutter_plugin_2/arcore_availability.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'ar_screen.dart';
import 'color_picker.dart';
import 'glb_recolor.dart';
import 'house_model.dart';
import 'house_viewer.dart';
import 'palette.dart';
import 'photo_screen.dart';
import 'saved_configs.dart';
import 'share_config.dart';

void main() => runApp(const GardenHouseApp());

class GardenHouseApp extends StatelessWidget {
  const GardenHouseApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'GardenHouse',
      debugShowCheckedModeBanner: false,
      themeMode: ThemeMode.system,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF178048)),
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF178048),
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      home: const ConfiguratorScreen(),
    );
  }
}

class ConfiguratorScreen extends StatefulWidget {
  const ConfiguratorScreen({super.key});

  @override
  State<ConfiguratorScreen> createState() => _ConfiguratorScreenState();
}

class _ConfiguratorScreenState extends State<ConfiguratorScreen> {
  late final Future<HouseModel> _model = HouseModel.load();
  late final Future<ArCoreAvailability> _arCore = checkArCoreAvailability();
  final _viewer = HouseViewerController();
  HousePart _part = HousePart.structure;
  bool _openingAr = false;
  bool _busy = false; // sharing or preparing a quote request
  bool _fullscreen = false;
  bool _dimensions = false;

  /// Real AR where ARCore is available, otherwise placing the house on a photo.
  Future<void> _openAr(HouseModel model) async {
    setState(() => _openingAr = true);
    try {
      final Widget screen;
      if (await _arCore == ArCoreAvailability.unsupported) {
        screen = PhotoScreen(model: model);
      } else {
        screen = ArScreen(model: model, glbPath: await model.exportGlb());
      }
      if (!mounted) return;
      // The preview would keep rendering under the AR screen.
      _viewer.setActive(false);
      await Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));
      _viewer.setActive(true);
    } finally {
      if (mounted) setState(() => _openingAr = false);
    }
  }

  Future<void> _withRender(
    Future<void> Function(Uint8List? render) action,
  ) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action(await _viewer.snapshot());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<HouseModel>(
      future: _model,
      builder: (context, snap) {
        if (snap.hasError) {
          return Scaffold(body: Center(child: Text('${snap.error}')));
        }
        if (!snap.hasData) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        final model = snap.data!;
        return ListenableBuilder(
          listenable: model,
          builder: (context, _) => _buildScaffold(context, model),
        );
      },
    );
  }

  Widget _buildScaffold(BuildContext context, HouseModel model) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('La tua Garden House'),
        centerTitle: false,
        actions: [
          IconButton(
            tooltip: 'Annulla',
            onPressed: model.canUndo ? model.undo : null,
            icon: const Icon(Icons.undo),
          ),
          IconButton(
            tooltip: 'Configurazioni salvate',
            onPressed: () => showSavedConfigs(context, model),
            icon: const Icon(Icons.bookmarks_outlined),
          ),
          IconButton(
            tooltip: 'Condividi',
            onPressed: _busy
                ? null
                : () => _withRender((png) => shareConfig(model.paints, png)),
            icon: const Icon(Icons.share_outlined),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openingAr ? null : () => _openAr(model),
        icon: _openingAr
            ? const SizedBox.square(
                dimension: 24,
                child: CircularProgressIndicator(strokeWidth: 2.5),
              )
            : const Icon(Icons.view_in_ar),
        label: const Text('Vedila nel tuo giardino'),
      ),
      body: LayoutBuilder(
        builder: (context, constraints) => Column(
          children: [
            Expanded(
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeInOut,
                margin: _fullscreen
                    ? EdgeInsets.zero
                    : const EdgeInsets.fromLTRB(16, 0, 16, 8),
                clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(_fullscreen ? 0 : 24),
                ),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    HouseViewer(
                      model: model,
                      controller: _viewer,
                      interactive: true,
                    ),
                    _buildViewControls(context),
                  ],
                ),
              ),
            ),
            AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeInOut,
              height: _fullscreen ? 0 : constraints.maxHeight * 0.52,
              child: _buildOptions(context, model),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildViewControls(BuildContext context) {
    Widget button(
      IconData icon,
      String tooltip,
      VoidCallback onPressed, {
      bool selected = false,
    }) => Padding(
      padding: const EdgeInsets.all(2),
      child: IconButton.filledTonal(
        tooltip: tooltip,
        isSelected: selected,
        visualDensity: VisualDensity.compact,
        style: IconButton.styleFrom(
          backgroundColor: Colors.white.withValues(alpha: .8),
          foregroundColor: Colors.black87,
        ),
        onPressed: onPressed,
        icon: Icon(icon, size: 20),
      ),
    );

    return Padding(
      padding: const EdgeInsets.all(8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              button(
                _fullscreen ? Icons.fullscreen_exit : Icons.fullscreen,
                _fullscreen ? 'Riduci' : 'Schermo intero',
                () => setState(() => _fullscreen = !_fullscreen),
              ),
              button(
                Icons.straighten,
                _dimensions ? 'Nascondi misure' : 'Mostra misure',
                () {
                  setState(() => _dimensions = !_dimensions);
                  _viewer.setDimensions(_dimensions);
                },
                selected: _dimensions,
              ),
            ],
          ),
          const Spacer(),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              button(Icons.crop_portrait, 'Vista frontale', () => _viewer.animateOrbit(0, 80)),
              button(Icons.crop_landscape, 'Vista laterale', () => _viewer.animateOrbit(90, 80)),
              button(Icons.vertical_align_bottom, 'Vista dall\'alto', () => _viewer.animateOrbit(35, 25)),
              button(Icons.threesixty, 'Ripristina vista', _viewer.resetView),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildOptions(BuildContext context, HouseModel model) {
    final paint = model.paints[_part]!;
    final swatches = _part == HousePart.structure
        ? structureSwatches
        : panelSwatches;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 96),
      children: [
        Text('Abbinamenti', style: theme.textTheme.titleSmall),
        const SizedBox(height: 8),
        SizedBox(
          height: 84,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: [
              _ComboTile(
                label: 'Sorprendimi',
                onTap: () {
                  HapticFeedback.selectionClick();
                  model.applyConfig(randomConfig());
                },
                child: CircleAvatar(
                  radius: 22,
                  backgroundColor: scheme.secondaryContainer,
                  child: Icon(
                    Icons.casino_outlined,
                    color: scheme.onSecondaryContainer,
                  ),
                ),
              ),
              for (final combo in combos)
                _ComboTile(
                  label: combo.name,
                  selected: combo.matches(model.paints),
                  onTap: () => model.applyConfig(combo.config),
                  child: ConfigSwatch(config: combo.config, size: 44),
                ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        SegmentedButton<HousePart>(
          segments: const [
            ButtonSegment(
              value: HousePart.structure,
              icon: Icon(Icons.home_work_outlined),
              label: Text('Struttura'),
            ),
            ButtonSegment(
              value: HousePart.panels,
              icon: Icon(Icons.view_quilt_outlined),
              label: Text('Pannelli'),
            ),
          ],
          selected: {_part},
          onSelectionChanged: (s) => setState(() => _part = s.first),
        ),
        if (_part == HousePart.panels) ...[
          const SizedBox(height: 16),
          Text('Finiture del catalogo', style: theme.textTheme.titleSmall),
          const SizedBox(height: 8),
          FinishChooser(
            selected: paint.texture,
            onChanged: (f) => model.setTexture(_part, f.id, f.rgb),
          ),
          const SizedBox(height: 4),
          Text(
            panelFinishById(paint.texture)?.name ?? '',
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
        ],
        const SizedBox(height: 16),
        Text(
          _part == HousePart.panels ? 'Altri colori' : 'Colore',
          style: theme.textTheme.titleSmall,
        ),
        const SizedBox(height: 8),
        ColorChooser(
          swatches: swatches,
          selected: paint.texture == null ? paint.color : null,
          onChanged: (rgb) => model.setColor(_part, rgb),
        ),
        const SizedBox(height: 20),
        Text('Finitura', style: theme.textTheme.titleSmall),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          children: [
            for (final f in Finish.values)
              ChoiceChip(
                label: Text(f.label),
                selected: paint.finish == f,
                onSelected: (_) => model.setFinish(_part, f),
              ),
          ],
        ),
        const SizedBox(height: 16),
        Text(
          'Colori e finiture sono indicativi; lo schermo può alterare le tonalità.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: scheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 16),
        FilledButton.tonalIcon(
          onPressed: _busy
              ? null
              : () => _withRender(
                  (png) => requestQuote(context, model.paints, png),
                ),
          icon: const Icon(Icons.request_quote_outlined),
          label: const Text('Richiedi preventivo'),
        ),
      ],
    );
  }
}

class _ComboTile extends StatelessWidget {
  const _ComboTile({
    required this.label,
    required this.onTap,
    required this.child,
    this.selected = false,
  });

  final String label;
  final VoidCallback onTap;
  final Widget child;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Material(
        color: selected ? scheme.primaryContainer : scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: SizedBox(
            width: 84,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                child,
                const SizedBox(height: 6),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelSmall,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
