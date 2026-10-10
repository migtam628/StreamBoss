import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../models/media.dart';
import '../screens/open_item.dart';
import '../screens/player_screen.dart';
import '../services/deck.dart';
import '../state/app_state.dart';
import '../widgets/net_image.dart';
import '../widgets/tv.dart';
import 'common.dart';
import 'ui_layout.dart';

const _ink = Color(0xFF10142E);

/// Deck's Home: a deck of picks for tonight. The top card is the pick; Left says "not tonight" (and the
/// title stays out for a month), Up saves it to My List, OK plays it and Down shows its page. On a phone,
/// swipe left to skip and right to save, and tap to play.
class DeckHome extends StatefulWidget {
  const DeckHome({super.key});

  @override
  State<DeckHome> createState() => _DeckHomeState();
}

class _DeckHomeState extends State<DeckHome> {
  List<DeckCard> _cards = const [];
  Object? _builtFor;
  int _gen = 0; // bumped by "New deck"
  int _i = 0; // how many cards have been dealt with
  String? _toast;
  Timer? _toastTimer;
  final _node = FocusNode(debugLabel: 'deck');

  @override
  void dispose() {
    _toastTimer?.cancel();
    _node.dispose();
    super.dispose();
  }

  void _ensure(AppState s) {
    final key = (identityHashCode(s.shown), _gen, DateTime.now().day);
    if (_builtFor == key) return;
    _builtFor = key;
    _i = 0;
    _cards = buildDeck(
      catalog: s.shown,
      recommendation: s.recommendation,
      recents: s.recents,
      favorites: s.favorites,
      skipped: s.deckSkippedKeys,
      seed: DateTime.now().day,
    );
  }

  DeckCard? get _top => _i < _cards.length ? _cards[_i] : null;

  void _say(String m) {
    setState(() => _toast = m);
    _toastTimer?.cancel();
    _toastTimer = Timer(const Duration(seconds: 2), () {
      if (mounted) setState(() => _toast = null);
    });
  }

  void _skip(AppState s) {
    final c = _top;
    if (c == null) return;
    s.skipForDeck(c.item);
    setState(() => _i++);
  }

  void _save(AppState s) {
    final c = _top;
    if (c == null) return;
    if (!s.isFavorite(c.item)) s.toggleFavorite(c.item);
    _say('${c.item.name} is in My List');
    setState(() => _i++);
  }

  void _play() {
    final c = _top;
    if (c == null) return;
    final it = c.item;
    if (it.kind == MediaKind.movie && it.streamUrl != null) {
      final at = context.read<AppState>().resumeFor(it);
      Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => PlayerScreen(
              title: it.name, url: it.streamUrl!, item: it, startAt: at)));
    } else {
      openItem(context, it); // a series opens on its episodes
    }
  }

  void _details() {
    final c = _top;
    if (c != null) openItem(context, c.item);
  }

  KeyEventResult _onKey(AppState s, KeyEvent e) {
    if (e is! KeyDownEvent) return KeyEventResult.ignored;
    final k = e.logicalKey;
    if (k == LogicalKeyboardKey.arrowLeft) {
      _skip(s);
    } else if (k == LogicalKeyboardKey.arrowUp) {
      _save(s);
    } else if (k == LogicalKeyboardKey.arrowDown) {
      // Down belongs to the deck only while there is a card; otherwise focus moves on.
      if (_top == null) return KeyEventResult.ignored;
      _details();
    } else if (k == LogicalKeyboardKey.enter ||
        k == LogicalKeyboardKey.select ||
        k == LogicalKeyboardKey.numpadEnter) {
      _play();
    } else {
      return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final p = LayoutPalette.of(context);
    final tv = TvScope.of(context);
    final wide = tv || MediaQuery.sizeOf(context).width >= 800;
    _ensure(s);
    final top = _top;

    Widget key(String glyph, String label, VoidCallback onTap,
            {bool go = false}) =>
        FocusSurface(
          radius: 14,
          semanticLabel: label,
          onTap: onTap,
          builder: (_, __) => Container(
            height: 52,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: go ? p.accent : p.text.withValues(alpha: 0.12),
              border: Border.all(
                  color: go ? p.accent : p.text.withValues(alpha: 0.4)),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(children: [
              Container(
                constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                    color: go ? _ink : p.text,
                    borderRadius: BorderRadius.circular(8)),
                child: Text(glyph,
                    style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 14,
                        color: go ? p.accent2 : p.bg)),
              ),
              const SizedBox(width: 10),
              Expanded(
                  child: Text(label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: go ? _ink : p.text))),
            ]),
          ),
        );

    final stack = LayoutBuilder(builder: (context, box) {
      final h = math.min(box.maxHeight * 0.92, box.maxWidth * 1.35);
      final w = h * 0.68;
      final cx = box.maxWidth / 2;
      final cy = box.maxHeight / 2;
      final children = <Widget>[];
      // Cards from the back of the pile to the front; one just dealt shows faded behind the pick.
      for (var o = 3; o >= -1; o--) {
        final idx = _i + o;
        if (idx < 0 || idx >= _cards.length) continue;
        final c = _cards[idx];
        final scale = o < 0 ? 0.9 : 1 - 0.07 * o;
        final cw = w * scale, ch = h * scale;
        final dx = o < 0 ? -w * 0.46 : o * w * 0.2;
        final dy = o * 6.0;
        final turns = (o < 0 ? -1 : o) * 0.0167;
        children.add(AnimatedPositioned(
          key: ValueKey(c.item.key),
          duration: const Duration(milliseconds: 260),
          curve: Curves.easeOutCubic,
          left: cx - cw / 2 + dx,
          top: cy - ch / 2 + dy,
          width: cw,
          height: ch,
          child: AnimatedRotation(
            turns: turns,
            duration: const Duration(milliseconds: 260),
            curve: Curves.easeOutCubic,
            child: AnimatedOpacity(
              opacity: o < 0 ? 0.35 : (o >= 3 ? 0.0 : 1.0),
              duration: const Duration(milliseconds: 260),
              child:
                  _CardFace(card: c, hero: o == 0, saved: s.isFavorite(c.item)),
            ),
          ),
        ));
      }
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _play,
        onHorizontalDragEnd: (d) {
          final v = d.primaryVelocity ?? 0;
          if (v < -250) {
            _skip(s);
          } else if (v > 250) {
            _save(s);
          }
        },
        child: Stack(clipBehavior: Clip.none, children: children),
      );
    });

    Widget info() =>
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('PICKED FOR YOU',
              style: TextStyle(
                  fontSize: 13,
                  letterSpacing: 2,
                  fontWeight: FontWeight.w800,
                  color: p.accent2)),
          const SizedBox(height: 8),
          Text(top!.item.name,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  fontSize: wide ? 40 : 28,
                  height: 1.05,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.5,
                  color: p.text)),
          const SizedBox(height: 8),
          Text(
            [
              if (top.item.kind == MediaKind.series) 'Series' else 'Movie',
              if (top.item.rating != null &&
                  top.item.rating!.isNotEmpty &&
                  top.item.rating != '0')
                '★ ${top.item.rating}'
            ].join(' · '),
            style: TextStyle(color: p.muted, fontSize: 16),
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
            decoration: BoxDecoration(
                color: p.text.withValues(alpha: 0.14),
                border: Border.all(color: p.text.withValues(alpha: 0.4)),
                borderRadius: BorderRadius.circular(20)),
            child: Text(top.reason,
                style: TextStyle(
                    fontWeight: FontWeight.w600, fontSize: 14, color: p.text)),
          ),
          if ((top.item.plot ?? '').isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(top.item.plot!,
                maxLines: wide ? 6 : 3,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: p.muted, fontSize: 15, height: 1.4)),
          ],
        ]);

    final pos = Row(mainAxisAlignment: MainAxisAlignment.center, children: [
      for (var k = 0; k < _cards.length; k++)
        AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          margin: const EdgeInsets.symmetric(horizontal: 3),
          width: k == _i ? 22 : 8,
          height: 8,
          decoration: BoxDecoration(
              color: k == _i
                  ? p.accent
                  : p.text.withValues(alpha: k < _i ? 0.15 : 0.35),
              borderRadius: BorderRadius.circular(4)),
        ),
      if (_cards.isNotEmpty) ...[
        const SizedBox(width: 12),
        Text(top == null ? 'done' : '${_i + 1} of ${_cards.length}',
            style: TextStyle(fontWeight: FontWeight.w700, color: p.text)),
      ],
    ]);

    final finished = Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(
              _cards.isEmpty
                  ? 'Nothing to pick from yet.'
                  : 'That was the deck.',
              style: TextStyle(
                  fontSize: 30, fontWeight: FontWeight.w800, color: p.text)),
          const SizedBox(height: 8),
          Text(
            _cards.isEmpty
                ? 'Movies and series from your library show up here, picked from what you watch and save.'
                : 'Titles you skipped stay out for a month. Saved ones are in My List.',
            textAlign: TextAlign.center,
            style: TextStyle(color: p.muted, fontSize: 16),
          ),
          const SizedBox(height: 18),
          Wrap(
              spacing: 10,
              runSpacing: 10,
              alignment: WrapAlignment.center,
              children: [
                SizedBox(
                    width: 190,
                    child: key('↻', 'New deck', () => setState(() => _gen++),
                        go: true)),
                if (s.deckSkips.isNotEmpty)
                  SizedBox(
                    width: 230,
                    child: key('✕', 'Forget my skips', () {
                      s.clearDeckSkips();
                      setState(() => _gen++);
                    }),
                  ),
              ]),
        ]),
      ),
    );

    Widget body;
    if (top == null) {
      body = finished;
    } else if (wide) {
      body = Row(children: [
        Expanded(
            flex: 26,
            child: Padding(
                padding: const EdgeInsets.fromLTRB(32, 8, 12, 8),
                child: SingleChildScrollView(child: info()))),
        Expanded(flex: 46, child: stack),
        Expanded(
          flex: 22,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 32, 8),
            child:
                Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              key('◀', 'Not tonight', () => _skip(s)),
              const SizedBox(height: 12),
              key('OK', 'Play', _play, go: true),
              const SizedBox(height: 12),
              key('▲', 'Save', () => _save(s)),
              const SizedBox(height: 12),
              key('▼', 'Details', _details),
            ]),
          ),
        ),
      ]);
    } else {
      body = Column(children: [
        Expanded(child: stack),
        Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
            child: Text(top.reason,
                textAlign: TextAlign.center,
                style: TextStyle(color: p.text, fontWeight: FontWeight.w600))),
        const SizedBox(height: 10),
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          _Round(
              icon: Icons.close, label: 'Not tonight', onTap: () => _skip(s)),
          const SizedBox(width: 22),
          _Round(
              icon: Icons.play_arrow, label: 'Play', onTap: _play, big: true),
          const SizedBox(width: 22),
          _Round(icon: Icons.add, label: 'Save', onTap: () => _save(s)),
        ]),
        const SizedBox(height: 10),
      ]);
    }

    return Focus(
      focusNode: _node,
      autofocus: tv,
      onKeyEvent: (_, e) => _onKey(s, e),
      child: ColoredBox(
        color: p.bg,
        child: Stack(children: [
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                    center: const Alignment(0, -0.2),
                    radius: 1.0,
                    colors: [p.surface, p.bg]),
              ),
            ),
          ),
          Column(children: [
            Expanded(child: body),
            if (top != null)
              Padding(
                  padding: const EdgeInsets.only(bottom: 10, top: 4),
                  child: pos),
          ]),
          if (_toast != null)
            // Across the top, where it covers no button; it never takes a tap.
            Positioned(
              left: 0,
              right: 0,
              top: 12,
              child: IgnorePointer(
                  child: Center(
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                  decoration: BoxDecoration(
                      color: _ink, borderRadius: BorderRadius.circular(24)),
                  child: Text(_toast!,
                      style: const TextStyle(
                          color: Colors.white, fontWeight: FontWeight.w600)),
                ),
              )),
            ),
        ]),
      ),
    );
  }
}

class _CardFace extends StatelessWidget {
  final DeckCard card;
  final bool hero, saved;
  const _CardFace(
      {required this.card, required this.hero, required this.saved});

  @override
  Widget build(BuildContext context) {
    final p = LayoutPalette.of(context);
    final it = card.item;
    final rating =
        it.rating != null && it.rating!.isNotEmpty && it.rating != '0'
            ? it.rating!
            : null;
    return Container(
      decoration: BoxDecoration(
        color: p.text,
        borderRadius: BorderRadius.circular(hero ? 22 : 18),
        boxShadow: [
          if (hero)
            BoxShadow(color: p.accent.withValues(alpha: 0.6), blurRadius: 28),
          const BoxShadow(
              color: Color(0x80030832), blurRadius: 18, offset: Offset(0, 10)),
        ],
        border: hero ? Border.all(color: p.accent, width: 4) : null,
      ),
      padding: const EdgeInsets.all(8),
      child: Column(children: [
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: Stack(fit: StackFit.expand, children: [
              DecoratedBox(
                  decoration: BoxDecoration(
                      gradient: LinearGradient(
                          colors: [p.accent, const Color(0xFF3A1B6B)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight))),
              if (it.poster != null && it.poster!.isNotEmpty)
                NetImage(it.poster!,
                    fit: BoxFit.cover, fallback: () => const SizedBox.shrink()),
              if (rating != null)
                Positioned(
                  left: 8,
                  top: 8,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                        color: _ink, borderRadius: BorderRadius.circular(6)),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.star, size: 14, color: p.accent2),
                      const SizedBox(width: 3),
                      Text(rating,
                          style: TextStyle(
                              color: p.accent2,
                              fontWeight: FontWeight.w800,
                              fontSize: 13)),
                    ]),
                  ),
                ),
              if (saved)
                const Positioned(
                    right: 8,
                    top: 8,
                    child: Icon(Icons.favorite, color: Colors.white, size: 20)),
            ]),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 8, 4, 2),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(it.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    color: _ink,
                    fontWeight: FontWeight.w800,
                    fontSize: hero ? 17 : 14)),
          ),
        ),
      ]),
    );
  }
}

class _Round extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool big;
  const _Round(
      {required this.icon,
      required this.label,
      required this.onTap,
      this.big = false});

  @override
  Widget build(BuildContext context) {
    final p = LayoutPalette.of(context);
    final d = big ? 68.0 : 54.0;
    return FocusSurface(
      radius: d / 2,
      semanticLabel: label,
      onTap: onTap,
      builder: (_, __) => Container(
        width: d,
        height: d,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: big ? p.accent : p.text.withValues(alpha: 0.14),
          border:
              Border.all(color: big ? p.accent : p.text.withValues(alpha: 0.5)),
        ),
        child: Icon(icon, size: big ? 34 : 26, color: big ? _ink : p.text),
      ),
    );
  }
}
