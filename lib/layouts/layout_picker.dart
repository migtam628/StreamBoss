import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../state/settings_state.dart';
import 'common.dart';
import 'ui_layout.dart';

/// Settings > Appearance > Layout: pick one of the looks. Each card draws a small
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
      UiLayout.daylight => Column(children: [
          Container(
            height: 14,
            color: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(children: [
              box(pal.accent, w: 6, h: 6, r: 3),
              const SizedBox(width: 6),
              box(const Color(0xFF111827), w: 20, h: 6, r: 4),
              const SizedBox(width: 4),
              box(const Color(0xFFCBD2DC), w: 14, h: 5, r: 4),
              const SizedBox(width: 4),
              box(const Color(0xFFCBD2DC), w: 14, h: 5, r: 4),
            ]),
          ),
          Expanded(
            flex: 5,
            child: Container(
              margin: const EdgeInsets.fromLTRB(8, 8, 8, 4),
              decoration: BoxDecoration(
                  color: Colors.white, borderRadius: BorderRadius.circular(6)),
              child: Row(children: [
                Expanded(
                    flex: 5,
                    child: Padding(
                        padding: const EdgeInsets.all(6),
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              box(const Color(0xFF111827), w: 46, h: 7),
                              const SizedBox(height: 3),
                              box(const Color(0xFFCBD2DC), w: 52, h: 3),
                              const SizedBox(height: 5),
                              box(pal.accent, w: 20, h: 7, r: 5),
                            ]))),
                Expanded(
                    flex: 4,
                    child: ClipRRect(
                        borderRadius: const BorderRadius.horizontal(
                            right: Radius.circular(6)),
                        child: _grad(
                            const Color(0xFF2B6CFF), const Color(0xFF0D1B5C)))),
              ]),
            ),
          ),
          Expanded(
            flex: 2,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(8, 0, 8, 6),
              child: Row(children: [
                for (var i = 0; i < 4; i++)
                  Expanded(
                      child: Container(
                          margin: EdgeInsets.only(right: i == 3 ? 0 : 3),
                          decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(3)),
                          alignment: Alignment.bottomLeft,
                          padding: const EdgeInsets.all(2),
                          child: box(pal.accent, w: 12, h: 2, r: 1)))
              ]),
            ),
          ),
        ]),
      UiLayout.cable => Stack(children: [
          Positioned.fill(
              child: Container(
                  decoration: const BoxDecoration(
                      gradient: RadialGradient(
                          center: Alignment(0.3, -0.2),
                          radius: 1.0,
                          colors: [Color(0xFF1F7C86), Color(0xFF05070A)])))),
          for (var i = 0; i < 14; i++)
            Positioned(
                left: 0,
                right: 0,
                top: 4.0 + i * 8,
                child: Container(height: 1.2, color: const Color(0x30000000))),
          Positioned(
              left: 10,
              top: 8,
              child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                Text('207',
                    style: TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 26,
                        height: 0.9,
                        color: pal.accent)),
                const SizedBox(width: 6),
                box(pal.accent2, w: 30, h: 4, r: 1),
              ])),
          Positioned(
              right: 8,
              top: 22,
              child: Column(children: [
                for (var i = 0; i < 4; i++)
                  Container(
                      margin: const EdgeInsets.only(bottom: 2),
                      width: 22,
                      height: 7,
                      decoration: BoxDecoration(
                          color: i == 2 ? pal.accent : Colors.transparent,
                          border: Border.all(color: pal.line)))
              ])),
          Positioned(
              left: 8,
              right: 8,
              bottom: 6,
              child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                      color: const Color(0xCC05070A),
                      border: Border.all(color: pal.line)),
                  child: Column(children: [
                    Row(children: [
                      box(pal.accent2, w: 10, h: 3, r: 1),
                      const SizedBox(width: 4),
                      box(pal.accent.withValues(alpha: 0.6), w: 46, h: 3, r: 1),
                    ]),
                    const SizedBox(height: 3),
                    Row(children: [
                      for (var i = 0; i < 5; i++)
                        Expanded(
                            child: Container(
                                margin: EdgeInsets.only(right: i == 4 ? 0 : 2),
                                height: 8,
                                color: i == 2 ? pal.accent : pal.line))
                    ]),
                  ]))),
        ]),
      UiLayout.indexList => Padding(
          padding: const EdgeInsets.fromLTRB(10, 8, 8, 8),
          child: Row(children: [
            Expanded(
              flex: 6,
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (var i = 0; i < 5; i++)
                      Container(
                          margin: const EdgeInsets.only(bottom: 3),
                          padding: const EdgeInsets.symmetric(horizontal: 3),
                          color: i == 1 ? pal.accent : Colors.transparent,
                          child: box(
                              i == 1
                                  ? pal.surfaceHi
                                  : Colors.white.withValues(alpha: 0.7),
                              w: [44, 50, 38, 34, 46][i].toDouble(),
                              h: 7,
                              r: 1)),
                  ]),
            ),
            const SizedBox(width: 8),
            Expanded(
              flex: 4,
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(height: 22, color: pal.surfaceHi),
                    const SizedBox(height: 4),
                    box(pal.accent, w: 26, h: 2, r: 1),
                    const SizedBox(height: 4),
                    box(Colors.white, w: 36, h: 3, r: 1),
                    const SizedBox(height: 2),
                    box(Colors.white54, w: 28, h: 2, r: 1),
                    const SizedBox(height: 4),
                    box(Colors.white, w: 32, h: 3, r: 1),
                  ]),
            ),
          ]),
        ),
      UiLayout.glass => Container(
          decoration: const BoxDecoration(
              gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFF0A4A5A), Color(0xFF1B3A8A), Color(0xFF2D1F6B)])),
          child: Stack(children: [
            Positioned(
                left: 10,
                right: 10,
                top: 10,
                height: 46,
                child: Container(
                    decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(9),
                        border: Border.all(color: Colors.white38)),
                    padding: const EdgeInsets.all(6),
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          box(Colors.white, w: 50, h: 7),
                          const SizedBox(height: 3),
                          box(Colors.white70, w: 64, h: 3),
                          const SizedBox(height: 5),
                          box(pal.accent, w: 20, h: 7, r: 5),
                        ]))),
            Positioned(
                left: 10,
                right: 10,
                top: 62,
                height: 22,
                child: Container(
                    decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.16),
                        borderRadius: BorderRadius.circular(7),
                        border: Border.all(color: Colors.white30)),
                    padding: const EdgeInsets.all(5),
                    child: Row(children: [
                      for (var i = 0; i < 3; i++) ...[
                        box(Colors.white30, w: 28, h: 10, r: 6),
                        const SizedBox(width: 4)
                      ]
                    ]))),
            Positioned(
                bottom: 6,
                left: 0,
                right: 0,
                child: Center(
                    child: Container(
                        width: 64,
                        height: 9,
                        decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.25),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.white38))))),
          ]),
        ),
      UiLayout.bento => Padding(
          padding: const EdgeInsets.all(2),
          child: Column(children: [
            Expanded(
              flex: 4,
              child: Row(children: [
                Expanded(flex: 6, child: ColoredBox(color: pal.accent, child: const SizedBox.expand())),
                const SizedBox(width: 2),
                Expanded(
                    flex: 4,
                    child: Column(children: [
                      Expanded(flex: 3, child: ColoredBox(color: pal.accent2, child: const SizedBox.expand())),
                      const SizedBox(height: 2),
                      const Expanded(flex: 2, child: ColoredBox(color: Color(0xFFF6F4F1), child: SizedBox.expand())),
                    ])),
                const SizedBox(width: 2),
                const Expanded(
                    flex: 3,
                    child: Column(children: [
                      Expanded(flex: 3, child: ColoredBox(color: Color(0xFF5FD36F), child: SizedBox.expand())),
                      SizedBox(height: 2),
                      Expanded(flex: 2, child: ColoredBox(color: Color(0xFFFFA3D1), child: SizedBox.expand())),
                    ])),
              ]),
            ),
            const SizedBox(height: 2),
            const Expanded(flex: 1, child: ColoredBox(color: Color(0xFF62B6FF), child: SizedBox.expand())),
          ]),
        ),
      UiLayout.library => Column(children: [
          Container(height: 10, color: pal.surface, alignment: Alignment.centerLeft, padding: const EdgeInsets.only(left: 6), child: box(pal.accent, w: 28, h: 3, r: 1)),
          Expanded(
            child: Row(children: [
              Container(
                  width: 44,
                  color: pal.surface,
                  padding: const EdgeInsets.all(5),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    for (var i = 0; i < 6; i++)
                      Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: Container(
                              color: i == 2 ? pal.accent.withValues(alpha: 0.3) : Colors.transparent,
                              child: box(i == 2 ? pal.accent : pal.muted, w: [30, 26, 32, 22, 28, 24][i].toDouble(), h: 3, r: 1))),
                  ])),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(6, 6, 6, 4),
                  child: Column(children: [
                    for (var i = 0; i < 5; i++)
                      Expanded(
                          child: Container(
                              decoration: BoxDecoration(
                                  color: i == 1 ? pal.accent.withValues(alpha: 0.18) : Colors.transparent,
                                  border: Border(bottom: BorderSide(color: pal.line))),
                              child: Row(children: [
                                box(pal.surfaceHi, w: 7, h: 10, r: 1),
                                const SizedBox(width: 4),
                                box(pal.text, w: [40, 34, 46, 30, 38][i].toDouble(), h: 3, r: 1),
                                const Spacer(),
                                box(pal.muted, w: 12, h: 2, r: 1),
                              ]))),
                  ]),
                ),
              ),
            ]),
          ),
        ]),
      UiLayout.orbit => Stack(children: [
          Positioned(
              left: -34,
              top: 6,
              child: Container(
                  width: 84,
                  height: 84,
                  decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: pal.accent.withValues(alpha: 0.7), width: 2)))),
          Positioned(
              left: -22,
              top: 18,
              child: Container(
                  width: 60,
                  height: 60,
                  decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: pal.line, width: 1)))),
          Positioned(left: 26, top: 40, child: box(pal.accent, w: 22, h: 8, r: 5)),
          Positioned(left: 24, top: 18, child: box(pal.accent2.withValues(alpha: 0.6), w: 16, h: 6, r: 4)),
          Positioned(left: 24, top: 62, child: box(pal.accent2.withValues(alpha: 0.6), w: 16, h: 6, r: 4)),
          Positioned(
              left: 66,
              right: 10,
              top: 12,
              child: Column(children: [
                for (var i = 0; i < 4; i++)
                  Padding(
                      padding: EdgeInsets.only(left: [8, 14, 14, 8][i].toDouble(), bottom: 4),
                      child: Container(
                          height: 12,
                          decoration: BoxDecoration(
                              color: i == 1 ? pal.accent : pal.surfaceHi,
                              borderRadius: BorderRadius.circular(5)))),
              ])),
        ]),
      UiLayout.mood => Container(
          decoration: const BoxDecoration(
              gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0xFF131E3B), Color(0xFF52507F), Color(0xFFD9A199)])),
          child: Padding(
              padding: const EdgeInsets.all(10),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                box(pal.accent, w: 24, h: 3, r: 2),
                const SizedBox(height: 4),
                box(Colors.white, w: 80, h: 7),
                const SizedBox(height: 8),
                Wrap(spacing: 4, runSpacing: 4, children: [
                  for (var i = 0; i < 6; i++)
                    box(i == 1 ? pal.accent : Colors.white.withValues(alpha: 0.25), w: 30, h: 10, r: 6),
                ]),
                const Spacer(),
                Row(children: [
                  for (var i = 0; i < 4; i++)
                    Padding(
                        padding: const EdgeInsets.only(right: 4),
                        child: box(Colors.white.withValues(alpha: 0.28), w: 22, h: 26, r: 4)),
                ]),
              ]))),
      UiLayout.mosaic => Container(
          color: const Color(0xFF14693A),
          padding: const EdgeInsets.all(6),
          child: Column(children: [
            Expanded(
                child: Column(children: [
              Expanded(
                  child: Row(children: [
                Expanded(child: Container(decoration: BoxDecoration(color: const Color(0xFF0B3A20), border: Border.all(color: pal.accent, width: 2)))),
                const SizedBox(width: 3),
                const Expanded(child: ColoredBox(color: Color(0xFF0B3A20), child: SizedBox.expand())),
              ])),
              const SizedBox(height: 3),
              const Expanded(
                  child: Row(children: [
                Expanded(child: ColoredBox(color: Color(0xFF0B3A20), child: SizedBox.expand())),
                SizedBox(width: 3),
                Expanded(child: ColoredBox(color: Color(0xFF0B3A20), child: SizedBox.expand())),
              ])),
            ])),
            const SizedBox(height: 4),
            Row(children: [
              for (var i = 0; i < 5; i++)
                Expanded(
                    child: Container(
                        margin: const EdgeInsets.only(right: 2),
                        height: 7,
                        color: i == 1 ? pal.accent : Colors.white24)),
            ]),
          ]),
        ),
      UiLayout.tonight => Padding(
          padding: const EdgeInsets.all(8),
          child: Row(children: [
            Expanded(
                flex: 6,
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  box(pal.text, w: 40, h: 8, r: 2),
                  const SizedBox(height: 3),
                  box(pal.accent.withValues(alpha: 0.7), w: 34, h: 3),
                  const SizedBox(height: 5),
                  for (var i = 0; i < 4; i++)
                    Padding(
                        padding: const EdgeInsets.only(bottom: 3),
                        child: Row(children: [
                          box(pal.muted, w: 8, h: 3),
                          const SizedBox(width: 3),
                          Container(
                              width: 5,
                              height: 5,
                              decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: i == 0 ? pal.accent : pal.bg,
                                  border: Border.all(color: pal.accent, width: 1))),
                          const SizedBox(width: 3),
                          Expanded(
                              child: Container(
                                  height: 11,
                                  decoration: BoxDecoration(
                                      color: pal.surface,
                                      borderRadius: BorderRadius.circular(3),
                                      border: Border.all(color: i == 0 ? pal.accent : pal.line, width: i == 0 ? 1.5 : 1)))),
                        ])),
                ])),
            const SizedBox(width: 6),
            Expanded(
                flex: 4,
                child: Container(
                    decoration: BoxDecoration(color: pal.text, borderRadius: BorderRadius.circular(4)),
                    padding: const EdgeInsets.all(4),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      box(pal.accent2, w: 40, h: 16, r: 2),
                      const SizedBox(height: 3),
                      box(pal.bg, w: 30, h: 4),
                      const SizedBox(height: 2),
                      box(pal.bg.withValues(alpha: 0.5), w: 36, h: 2),
                      const Spacer(),
                      box(pal.accent, w: 28, h: 7, r: 3),
                    ]))),
          ]),
        ),
      UiLayout.globe => Padding(
          padding: const EdgeInsets.all(8),
          child: Row(children: [
            Expanded(
                flex: 6,
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Expanded(
                      child: Stack(children: [
                    for (final (l, t, w, h) in const [(2.0, 4.0, 22.0, 14.0), (30.0, 3.0, 16.0, 12.0), (8.0, 24.0, 12.0, 14.0), (34.0, 20.0, 18.0, 16.0)])
                      Positioned(left: l, top: t, child: box(pal.accent2.withValues(alpha: 0.55), w: w, h: h, r: 3)),
                    Positioned(left: 34, top: 14, child: Container(width: 8, height: 8, decoration: BoxDecoration(shape: BoxShape.circle, color: pal.accent))),
                  ])),
                  box(Colors.white, w: 36, h: 7, r: 2),
                  const SizedBox(height: 3),
                  Row(children: [for (var i = 0; i < 3; i++) Padding(padding: const EdgeInsets.only(right: 3), child: box(i == 0 ? pal.accent : pal.line, w: 12, h: 5, r: 3))]),
                ])),
            const SizedBox(width: 6),
            Expanded(
                flex: 4,
                child: Container(
                    decoration: BoxDecoration(color: pal.surface, borderRadius: BorderRadius.circular(4), border: Border.all(color: pal.line)),
                    padding: const EdgeInsets.all(3),
                    child: Column(children: [
                      for (var i = 0; i < 4; i++)
                        Padding(padding: const EdgeInsets.only(bottom: 3), child: box(i == 0 ? pal.surfaceHi : pal.line, w: 60, h: 9, r: 3)),
                    ]))),
          ]),
        ),
      UiLayout.playground => Padding(
          padding: const EdgeInsets.all(8),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Container(width: 10, height: 10, decoration: BoxDecoration(shape: BoxShape.circle, color: pal.accent)),
              const SizedBox(width: 4),
              box(pal.text, w: 28, h: 6, r: 2),
            ]),
            const SizedBox(height: 5),
            Expanded(
                child: Row(children: [
              Expanded(flex: 4, child: Container(decoration: BoxDecoration(color: pal.accent2, borderRadius: BorderRadius.circular(5)))),
              const SizedBox(width: 4),
              Expanded(
                  flex: 5,
                  child: GridView.count(
                      crossAxisCount: 3,
                      mainAxisSpacing: 3,
                      crossAxisSpacing: 3,
                      physics: const NeverScrollableScrollPhysics(),
                      children: [
                        for (final c in const [Color(0xFFFF5A5F), Color(0xFF7C5CFF), Color(0xFF2FB8CC), Color(0xFF3FC46A), Color(0xFFFFD23F), Color(0xFFFF9F45)])
                          Container(decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(4))),
                      ])),
            ])),
          ]),
        ),
      UiLayout.console => Padding(
          padding: const EdgeInsets.all(8),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(
                height: 14,
                padding: const EdgeInsets.symmetric(horizontal: 4),
                decoration: BoxDecoration(border: Border.all(color: pal.accent, width: 1.5), borderRadius: BorderRadius.circular(3)),
                child: Row(children: [box(pal.accent, w: 4, h: 6, r: 1), const SizedBox(width: 3), box(pal.text, w: 18, h: 4), box(pal.accent, w: 3, h: 7, r: 0)])),
            const SizedBox(height: 4),
            Row(children: [for (var i = 0; i < 3; i++) Padding(padding: const EdgeInsets.only(right: 3), child: box(i == 0 ? pal.accent : pal.line, w: 12, h: 5, r: 2))]),
            const SizedBox(height: 5),
            for (var i = 0; i < 5; i++)
              Padding(
                  padding: const EdgeInsets.only(bottom: 2),
                  child: Container(
                      height: 7,
                      color: i == 2 ? pal.accent : Colors.transparent,
                      child: Row(children: [const SizedBox(width: 3), box(i == 2 ? pal.bg : pal.muted, w: 6, h: 3), const SizedBox(width: 4), box(i == 2 ? pal.bg : pal.text, w: 36 + i * 4.0, h: 3)]))),
          ]),
        ),
      UiLayout.deck => Padding(
          padding: const EdgeInsets.all(8),
          child: Row(children: [
            Expanded(
                flex: 3,
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  box(pal.accent2, w: 22, h: 3),
                  const SizedBox(height: 3),
                  box(pal.text, w: 34, h: 8),
                  const SizedBox(height: 3),
                  box(pal.muted, w: 30, h: 3),
                ])),
            Expanded(
                flex: 4,
                child: Stack(alignment: Alignment.center, children: [
                  Transform.rotate(angle: 0.2, child: Transform.translate(offset: const Offset(14, 0), child: box(pal.text.withValues(alpha: 0.7), w: 24, h: 34, r: 4))),
                  Transform.rotate(angle: 0.1, child: Transform.translate(offset: const Offset(7, 0), child: box(pal.text.withValues(alpha: 0.85), w: 26, h: 36, r: 4))),
                  Container(width: 28, height: 40, decoration: BoxDecoration(color: pal.text, borderRadius: BorderRadius.circular(4), border: Border.all(color: pal.accent, width: 2))),
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
