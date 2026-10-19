import 'package:flutter/material.dart';

import 'palette.dart';

/// Grid of preset swatches plus a "custom" tile that opens an HSV picker.
class ColorChooser extends StatelessWidget {
  const ColorChooser({
    super.key,
    required this.swatches,
    required this.selected,
    required this.onChanged,
  });

  final List<Swatch> swatches;

  /// The current color, or null when none of these is current (a panel
  /// finish is).
  final int? selected;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final selected = this.selected;
    final isPreset =
        selected == null || swatches.any((s) => s.rgb == selected);
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        for (final s in swatches)
          _Dot(
            color: s.color,
            tooltip: s.name,
            selected: s.rgb == selected,
            onTap: () => onChanged(s.rgb),
          ),
        _Dot(
          color: isPreset ? null : Color(0xFF000000 | selected),
          tooltip: 'Colore personalizzato',
          selected: !isPreset,
          child: const Icon(Icons.colorize, size: 18),
          onTap: () async {
            final picked = await showModalBottomSheet<int>(
              context: context,
              isScrollControlled: true,
              showDragHandle: true,
              builder: (_) => _HsvSheet(initial: selected ?? 0x9DA6A1),
            );
            if (picked != null) onChanged(picked);
          },
        ),
      ],
    );
  }
}

/// The brochure's panel finishes, as round crops of their photos.
class FinishChooser extends StatelessWidget {
  const FinishChooser({
    super.key,
    required this.selected,
    required this.onChanged,
  });

  /// Id of the current finish, if any.
  final String? selected;
  final ValueChanged<PanelFinish> onChanged;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        for (final f in panelFinishes)
          _Dot(
            color: f.color,
            image: AssetImage(f.thumbnail),
            tooltip: f.name,
            selected: f.id == selected,
            onTap: () => onChanged(f),
          ),
      ],
    );
  }
}

class _Dot extends StatelessWidget {
  const _Dot({
    required this.tooltip,
    required this.selected,
    required this.onTap,
    this.color,
    this.image,
    this.child,
  });

  final Color? color;
  final ImageProvider? image;
  final String tooltip;
  final bool selected;
  final VoidCallback onTap;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Tooltip(
      message: tooltip,
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: color,
            image: image == null
                ? null
                : DecorationImage(image: image!, fit: BoxFit.cover),
            gradient: color == null
                ? const SweepGradient(
                    colors: [
                      Colors.red,
                      Colors.yellow,
                      Colors.green,
                      Colors.cyan,
                      Colors.blue,
                      Colors.purple,
                      Colors.red,
                    ],
                  )
                : null,
            border: Border.all(
              color: selected ? scheme.primary : scheme.outlineVariant,
              width: selected ? 3 : 1,
            ),
            boxShadow: selected
                ? [
                    BoxShadow(
                      color: scheme.primary.withValues(alpha: .35),
                      blurRadius: 8,
                    ),
                  ]
                : null,
          ),
          child: child,
        ),
      ),
    );
  }
}

class _HsvSheet extends StatefulWidget {
  const _HsvSheet({required this.initial});
  final int initial;

  @override
  State<_HsvSheet> createState() => _HsvSheetState();
}

class _HsvSheetState extends State<_HsvSheet> {
  late HSVColor hsv = HSVColor.fromColor(Color(0xFF000000 | widget.initial));

  int get rgb => hsv.toColor().toARGB32() & 0xFFFFFF;

  @override
  Widget build(BuildContext context) {
    final hex = rgb.toRadixString(16).padLeft(6, '0').toUpperCase();
    return Padding(
      padding: EdgeInsets.fromLTRB(
        24,
        0,
        24,
        24 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            height: 64,
            decoration: BoxDecoration(
              color: hsv.toColor(),
              borderRadius: BorderRadius.circular(16),
            ),
            alignment: Alignment.center,
            child: Text(
              '#$hex',
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: hsv.toColor().computeLuminance() > .5
                    ? Colors.black
                    : Colors.white,
              ),
            ),
          ),
          const SizedBox(height: 12),
          _slider(
            'Tonalità',
            hsv.hue,
            360,
            (v) => hsv = hsv.withHue(v),
            track: [
              for (var h = 0; h <= 360; h += 60)
                HSVColor.fromAHSV(1, h.toDouble(), 1, 1).toColor(),
            ],
          ),
          _slider(
            'Saturazione',
            hsv.saturation,
            1,
            (v) => hsv = hsv.withSaturation(v),
            track: [
              HSVColor.fromAHSV(1, hsv.hue, 0, hsv.value).toColor(),
              HSVColor.fromAHSV(1, hsv.hue, 1, hsv.value).toColor(),
            ],
          ),
          _slider(
            'Luminosità',
            hsv.value,
            1,
            (v) => hsv = hsv.withValue(v),
            track: [
              Colors.black,
              HSVColor.fromAHSV(1, hsv.hue, hsv.saturation, 1).toColor(),
            ],
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: () => Navigator.pop(context, rgb),
              child: const Text('Usa questo colore'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _slider(
    String label,
    double value,
    double max,
    void Function(double) apply, {
    required List<Color> track,
  }) {
    return Row(
      children: [
        SizedBox(width: 96, child: Text(label)),
        Expanded(
          child: Stack(
            alignment: Alignment.center,
            children: [
              Container(
                height: 10,
                margin: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(5),
                  gradient: LinearGradient(colors: track),
                ),
              ),
              SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  trackHeight: 0,
                  activeTrackColor: Colors.transparent,
                  inactiveTrackColor: Colors.transparent,
                ),
                child: Slider(
                  value: value.clamp(0, max),
                  max: max,
                  onChanged: (v) => setState(() => apply(v)),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
