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
          final per = c.maxWidth >= 840 ? 3 : 2;
          return Column(children: [
            for (var i = 0; i < cards.length; i += per)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (var k = 0; k < per; k++)
                        Expanded(
                            child: Padding(
                                padding: EdgeInsets.only(
                                    right: k == per - 1 ? 0 : 12),
                                child: i + k < cards.length
                                    ? cards[i + k]
                                    : const SizedBox())),
                    ]),
              ),
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

  Widget _grad(Color a, Color b) => Container(
      decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(5),
          gradient: LinearGradient(colors: [a, b])));

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
      UiLayout.prime => Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 6, 8, 4),
            child: Row(children: [
              box(pal.surfaceHi, w: 30, h: 22, r: 3),
              const SizedBox(width: 6),
              Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                    box(pal.accent2, w: 36, h: 4),
                    const SizedBox(height: 3),
                    box(Colors.white, w: 60, h: 7),
                    const SizedBox(height: 3),
                    box(soft, w: 44, h: 3)
                  ])),
            ]),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(8, 0, 8, 6),
              child: Column(children: [
                for (var r = 0; r < 4; r++)
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 3),
                      child: Row(children: [
                        for (final f in (r == 1 ? [5, 3, 5] : [4, 6, 3]))
                          Expanded(
                            flex: f,
                            child: Padding(
                              padding: const EdgeInsets.only(right: 2),
                              child: Container(
                                decoration: BoxDecoration(
                                  color: r == 1 && f == 5
                                      ? pal.surfaceHi
                                      : pal.surface,
                                  borderRadius: BorderRadius.circular(3),
                                  border: r == 1 && f == 5
                                      ? Border.all(
                                          color: Colors.white, width: 1.2)
                                      : null,
                                ),
                              ),
                            ),
                          ),
                      ]),
                    ),
                  ),
              ]),
            ),
          ),
        ]),
      UiLayout.coverflow => Column(children: [
          const SizedBox(height: 6),
          Expanded(
            child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  for (final w in [8.0, 12.0, 18.0, 12.0, 8.0])
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 2),
                      child: Opacity(
                        opacity: w == 18 ? 1 : (w == 12 ? 0.7 : 0.4),
                        child: Container(
                          width: w * 1.4,
                          height: w * 2.1,
                          decoration: BoxDecoration(
                            color: w == 18 ? pal.accent : soft,
                            borderRadius: BorderRadius.circular(3),
                            border: w == 18
                                ? Border.all(color: Colors.white, width: 1.2)
                                : null,
                          ),
                        ),
                      ),
                    ),
                ]),
          ),
          box(Colors.white, w: 40, h: 6),
          const SizedBox(height: 4),
          box(pal.accent, w: 26, h: 7, r: 5),
          const SizedBox(height: 6),
        ]),
      UiLayout.hub => Padding(
          padding: const EdgeInsets.all(8),
          child: Column(children: [
            Align(
                alignment: Alignment.centerLeft,
                child: box(Colors.white, w: 50, h: 6)),
            const SizedBox(height: 6),
            Expanded(
              flex: 5,
              child: Row(children: [
                Expanded(
                    flex: 3,
                    child: _grad(
                        const Color(0xFF1FC4AF), const Color(0xFF0B5F78))),
                const SizedBox(width: 3),
                Expanded(
                    flex: 2,
                    child: Column(children: [
                      Expanded(
                          child: _grad(const Color(0xFFFF5D8F),
                              const Color(0xFFA3214F))),
                      const SizedBox(height: 3),
                      Expanded(
                          child: _grad(
                              const Color(0xFF8C6BFF), const Color(0xFF43228F)))
                    ])),
                const SizedBox(width: 3),
                Expanded(
                    flex: 2,
                    child: Column(children: [
                      Expanded(
                          child: _grad(const Color(0xFF4C8DFF),
                              const Color(0xFF1C3F96))),
                      const SizedBox(height: 3),
                      Expanded(
                          child: _grad(
                              const Color(0xFFFFB02E), const Color(0xFFB25A0A)))
                    ])),
              ]),
            ),
            const SizedBox(height: 6),
            Expanded(
                flex: 2,
                child: Row(children: [
                  for (var i = 0; i < 3; i++)
                    Expanded(
                        child: Padding(
                            padding: const EdgeInsets.only(right: 3),
                            child: box(soft)))
                ])),
          ]),
        ),
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
