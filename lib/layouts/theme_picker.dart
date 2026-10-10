import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../state/settings_state.dart';
import 'common.dart';
import 'ui_layout.dart';

/// Accent colors to pick from. A hue slider covers the rest.
const accentChoices = <Color>[
  Color(0xFFFF3D71),
  Color(0xFFFF6A3D),
  Color(0xFFFFB02E),
  Color(0xFF2FBF8F),
  Color(0xFF14B8A6),
  Color(0xFF4C8DFF),
  Color(0xFF7D6DFF),
  Color(0xFFD946EF),
];

Color accentFromHue(double hue) =>
    HSVColor.fromAHSV(1, hue.clamp(0, 360).toDouble(), 0.78, 1).toColor();

/// Settings > Appearance > Colors: the accent and the background, on top of any layout.
class ThemePicker extends StatelessWidget {
  const ThemePicker({super.key});

  @override
  Widget build(BuildContext context) {
    final st = context.watch<SettingsState>();
    final p = LayoutPalette.of(context);
    final cur = st.accent;
    final hue = cur == null ? 330.0 : HSVColor.fromColor(cur).hue;
    final painted = st.layout == UiLayout.glass ||
        st.layout == UiLayout.mosaic;

    Widget swatch(Color? c, {required String label}) {
      final on = cur?.toARGB32() == c?.toARGB32();
      return FocusSurface(
        radius: 22,
        semanticLabel: label,
        onTap: () => st.set('accentColor', c == null ? 0 : c.toARGB32()),
        builder: (_, __) => Container(
          width: 44,
          height: 44,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: c ?? p.wash(0.14),
            shape: BoxShape.circle,
            border:
                Border.all(color: on ? p.text : Colors.transparent, width: 3),
          ),
          child: c == null
              ? Icon(Icons.auto_awesome, size: 20, color: p.text)
              : on
                  ? Icon(Icons.check,
                      size: 22,
                      color: c.computeLuminance() > 0.5
                          ? Colors.black
                          : Colors.white)
                  : null,
        ),
      );
    }

    Widget bgChip(
        String key, String label, Color bg, Color surface, Color text) {
      final on = st.background == key;
      return FocusSurface(
        radius: 14,
        semanticLabel: '$label background',
        onTap: () => st.set('background', key),
        builder: (_, __) => Container(
          width: 108,
          padding: const EdgeInsets.all(8),
          color: p.wash(on ? 0.18 : 0.08),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
              height: 44,
              decoration: BoxDecoration(
                color: bg,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                    color: on ? p.accent : p.wash(0.2), width: on ? 2.5 : 1),
              ),
              child: Align(
                alignment: Alignment.bottomLeft,
                child: Container(
                  margin: const EdgeInsets.all(6),
                  width: 46,
                  height: 14,
                  decoration: BoxDecoration(
                      color: surface, borderRadius: BorderRadius.circular(4)),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Container(
                        margin: const EdgeInsets.only(left: 4),
                        width: 18,
                        height: 4,
                        color: text),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 6),
            Text(label,
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: on ? FontWeight.w800 : FontWeight.w500)),
          ]),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Accent color',
            style: TextStyle(color: p.muted, fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        Wrap(spacing: 10, runSpacing: 10, children: [
          swatch(null, label: 'The layout\'s own accent'),
          for (final c in accentChoices)
            swatch(c, label: 'Accent color ${c.toARGB32().toRadixString(16)}'),
        ]),
        Row(children: [
          const Icon(Icons.palette_outlined, size: 20),
          Expanded(
            child: Slider(
              value: hue.clamp(0, 360).toDouble(),
              max: 360,
              divisions: 72,
              label: 'Hue',
              activeColor: cur ?? p.accent,
              onChanged: (v) =>
                  st.set('accentColor', accentFromHue(v).toARGB32()),
            ),
          ),
        ]),
        const SizedBox(height: 4),
        Text('Background',
            style: TextStyle(color: p.muted, fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        Wrap(spacing: 10, runSpacing: 10, children: [
          bgChip(
              'layout',
              'Layout',
              LayoutPalette.forLayout(st.layout).bg,
              LayoutPalette.forLayout(st.layout).surface,
              LayoutPalette.forLayout(st.layout).text),
          for (final e in LayoutPalette.backgrounds.entries)
            bgChip(e.key, e.value.$1, e.value.$2, e.value.$3, e.value.$5),
        ]),
        if (painted)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
                '${st.layout.label} paints its own backdrop, so only the accent changes there.',
                style: TextStyle(color: p.muted, fontSize: 13)),
          ),
      ]),
    );
  }
}
