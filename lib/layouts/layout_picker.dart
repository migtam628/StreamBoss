import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../state/settings_state.dart';
import 'common.dart';
import 'ui_layout.dart';

/// Settings > Appearance > Layout: pick one of the three looks. Each card draws a small
/// wireframe of the layout in its own colors.
class LayoutPicker extends StatelessWidget {
  const LayoutPicker({super.key});

  @override
  Widget build(BuildContext context) {
    final st = context.watch<SettingsState>();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      child: LayoutBuilder(builder: (context, c) {
        final cards = [
          for (final l in UiLayout.values)
            _LayoutCard(
                layout: l,
                selected: st.layout == l,
                onTap: () => st.set('layout', l.name)),
        ];
        if (c.maxWidth >= 640) {
          return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            for (final w in cards)
              Expanded(
                  child: Padding(
                      padding: const EdgeInsets.only(right: 12), child: w)),
          ]);
        }
        return Column(children: [
          for (final w in cards)
            Padding(padding: const EdgeInsets.only(bottom: 10), child: w)
        ]);
      }),
    );
  }
}

class _LayoutCard extends StatelessWidget {
  final UiLayout layout;
  final bool selected;
  final VoidCallback onTap;
  const _LayoutCard(
      {required this.layout, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final pal = LayoutPalette.forLayout(layout);
    final cur = LayoutPalette.of(context);
    return FocusSurface(
      radius: 16,
      semanticLabel: '${layout.label}${selected ? ', selected' : ''}',
      onTap: onTap,
      builder: (_, __) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: cur.surface,
          border: Border.all(
              color: selected ? cur.accent : Colors.transparent, width: 2),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          AspectRatio(
              aspectRatio: 16 / 9, child: _Wireframe(layout: layout, pal: pal)),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(
                child: Text(layout.label,
                    style: const TextStyle(
                        fontSize: 17, fontWeight: FontWeight.w800))),
            if (selected) Icon(Icons.check_circle, color: cur.accent, size: 20),
          ]),
          const SizedBox(height: 4),
          Text(layout.blurb,
              style: TextStyle(color: cur.muted, fontSize: 13, height: 1.3)),
        ]),
      ),
    );
  }
}

/// A tiny abstract drawing of each layout.
class _Wireframe extends StatelessWidget {
  final UiLayout layout;
  final LayoutPalette pal;
  const _Wireframe({required this.layout, required this.pal});

  Widget box(Color c, {double? w, double? h, double r = 3}) => Container(
      width: w,
      height: h,
      decoration:
          BoxDecoration(color: c, borderRadius: BorderRadius.circular(r)));

  @override
  Widget build(BuildContext context) {
    final soft = Colors.white.withValues(alpha: 0.14);
    final Widget inner = switch (layout) {
      UiLayout.marquee => Row(children: [
          Container(
              width: 16,
              color: Colors.white10,
              child: Column(children: [
                const SizedBox(height: 8),
                for (var i = 0; i < 4; i++)
                  Padding(
                      padding: const EdgeInsets.symmetric(vertical: 3),
                      child: box(i == 0 ? pal.accent : soft, w: 8, h: 8))
              ])),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                        flex: 5,
                        child: Container(
                            decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(5),
                                gradient: LinearGradient(colors: [
                                  pal.accent.withValues(alpha: 0.7),
                                  const Color(0xFF3B1055)
                                ])),
                            alignment: Alignment.bottomLeft,
                            padding: const EdgeInsets.all(6),
                            child: box(pal.accent, w: 28, h: 8, r: 4))),
                    const SizedBox(height: 6),
                    Expanded(
                        flex: 3,
                        child: Row(children: [
                          for (var i = 0; i < 4; i++)
                            Expanded(
                                child: Padding(
                                    padding: const EdgeInsets.only(right: 4),
                                    child: box(soft)))
                        ])),
                  ]),
            ),
          ),
        ]),
      UiLayout.control => Column(children: [
          Container(
              height: 12,
              color: pal.surface,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Row(children: [
                box(pal.accent, w: 22, h: 4),
                const SizedBox(width: 8),
                box(soft, w: 14, h: 4),
                const SizedBox(width: 4),
                box(soft, w: 14, h: 4)
              ])),
          Expanded(
            child: Row(children: [
              Container(
                  width: 26,
                  padding: const EdgeInsets.all(4),
                  child: Column(children: [
                    for (var i = 0; i < 4; i++)
                      Padding(
                          padding: const EdgeInsets.only(bottom: 3),
                          child: box(i == 1 ? pal.surfaceHi : soft, h: 5))
                  ])),
              Expanded(
                  child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Column(children: [
                        for (var i = 0; i < 4; i++)
                          Padding(
                              padding: const EdgeInsets.only(bottom: 3),
                              child: box(
                                  i == 1
                                      ? pal.surfaceHi
                                      : soft.withValues(alpha: 0.08),
                                  h: 9,
                                  r: 2))
                      ]))),
              Container(
                  width: 40,
                  padding: const EdgeInsets.all(4),
                  child: Column(children: [
                    box(pal.surfaceHi, h: 18),
                    const SizedBox(height: 3),
                    box(soft, h: 4),
                    const SizedBox(height: 2),
                    box(soft, h: 4)
                  ])),
            ]),
          ),
        ]),
      UiLayout.spotlight => Column(children: [
          const SizedBox(height: 5),
          box(Colors.white24, w: 64, h: 8, r: 5),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Row(children: [
                Expanded(
                    flex: 4,
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          box(Colors.white, w: 44, h: 8),
                          const SizedBox(height: 4),
                          box(soft, w: 50, h: 3),
                          const SizedBox(height: 2),
                          box(soft, w: 40, h: 3),
                          const Spacer(),
                          box(Colors.white, w: 22, h: 8, r: 5)
                        ])),
                Expanded(
                    flex: 6,
                    child: GridView.count(
                        crossAxisCount: 3,
                        mainAxisSpacing: 3,
                        crossAxisSpacing: 3,
                        childAspectRatio: 0.72,
                        physics: const NeverScrollableScrollPhysics(),
                        children: [
                          for (var i = 0; i < 6; i++)
                            Container(
                                decoration: BoxDecoration(
                                    color: i == 1 ? pal.accent : soft,
                                    borderRadius: BorderRadius.circular(3),
                                    border: i == 1
                                        ? Border.all(
                                            color: Colors.white, width: 1.5)
                                        : null))
                        ])),
              ]),
            ),
          ),
        ]),
    };
    return ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: ColoredBox(color: pal.bg, child: inner));
  }
}
