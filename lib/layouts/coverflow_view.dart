import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../models/media.dart';
import '../screens/open_item.dart';
import '../state/app_state.dart';
import '../widgets/net_image.dart';
import '../widgets/tv.dart';
import 'common.dart';
import 'ui_layout.dart';

/// Coverflow: one title large in the middle, its neighbors fanned out on both sides. Left and
/// Right (or a swipe) flip through them; OK plays the middle one. Chips above pick a section.
class CoverflowView extends StatefulWidget {
  /// (chip label, items) pairs. The first is shown at the start.
  final List<(String, List<MediaItem>)> sections;
  const CoverflowView({super.key, required this.sections});

  @override
  State<CoverflowView> createState() => _CoverflowViewState();
}

class _CoverflowViewState extends State<CoverflowView> {
  int _sec = 0;
  int _index = 0;
  bool _hasFocus = false;
  PageController? _pc;
  double? _fraction;

  PageController _controller(double fraction) {
    if (_pc == null || _fraction != fraction) {
      _pc?.dispose();
      _fraction = fraction;
      _pc = PageController(viewportFraction: fraction, initialPage: _index);
    }
    return _pc!;
  }

  @override
  void dispose() {
    _pc?.dispose();
    super.dispose();
  }

  void _go(int i, int count) {
    final to = i.clamp(0, math.max(0, count - 1)).toInt();
    if (to == _index) return;
    setState(() => _index = to);
    _pc?.animateToPage(to,
        duration: const Duration(milliseconds: 220), curve: Curves.easeOut);
  }

  @override
  Widget build(BuildContext context) {
    final p = LayoutPalette.of(context);
    final tv = TvScope.of(context);
    final wide = tv || MediaQuery.sizeOf(context).width >= 800;
    final secs = widget.sections;
    if (secs.isEmpty || secs.every((e) => e.$2.isEmpty)) {
      return Center(
          child: Text('Nothing here yet.', style: TextStyle(color: p.muted)));
    }
    final sec = _sec.clamp(0, secs.length - 1).toInt();
    final items = secs[sec].$2;
    final index = _index.clamp(0, math.max(0, items.length - 1)).toInt();
    final cur = items.isEmpty ? null : items[index];
    final live =
        items.isNotEmpty && items.every((e) => e.kind == MediaKind.live);
    final app = context.watch<AppState>();
    final controller = _controller(wide ? 0.2 : 0.62);

    return Column(children: [
      ChipRow(
        labels: [for (final e in secs) e.$1],
        selected: sec,
        onSelect: (i) => setState(() {
          _sec = i;
          _index = 0;
          _pc?.dispose();
          _pc = null;
        }),
      ),
      Expanded(
        child: Focus(
          autofocus: tv,
          onFocusChange: (f) => setState(() => _hasFocus = f),
          onKeyEvent: (node, e) {
            if (e is! KeyDownEvent && e is! KeyRepeatEvent) {
              return KeyEventResult.ignored;
            }
            final k = e.logicalKey;
            if (k == LogicalKeyboardKey.arrowLeft) {
              _go(index - 1, items.length);
              return KeyEventResult.handled;
            }
            if (k == LogicalKeyboardKey.arrowRight) {
              _go(index + 1, items.length);
              return KeyEventResult.handled;
            }
            if ((k == LogicalKeyboardKey.select ||
                    k == LogicalKeyboardKey.enter ||
                    k == LogicalKeyboardKey.numpadEnter) &&
                cur != null) {
              openItem(context, cur, queue: live ? items : null);
              return KeyEventResult.handled;
            }
            return KeyEventResult.ignored;
          },
          child: PageView.builder(
            key: ValueKey('cf-$sec-${wide ? 'w' : 'n'}'),
            controller: controller,
            itemCount: items.length,
            onPageChanged: (i) => setState(() => _index = i),
            clipBehavior: Clip.none,
            itemBuilder: (_, i) => AnimatedBuilder(
              animation: controller,
              builder: (_, __) {
                final page =
                    controller.hasClients && controller.position.haveDimensions
                        ? (controller.page ?? index.toDouble())
                        : index.toDouble();
                final d = (page - i).clamp(-3.0, 3.0);
                final scale = (1 - d.abs() * 0.16).clamp(0.55, 1.0);
                final opacity = (1 - d.abs() * 0.28).clamp(0.25, 1.0);
                final focused = i == index && _hasFocus;
                return Center(
                  child: Opacity(
                    opacity: opacity,
                    child: Transform(
                      alignment: Alignment.center,
                      transform: Matrix4.identity()
                        ..setEntry(3, 2, 0.0012)
                        ..rotateY(-d.clamp(-1.0, 1.0) * 0.5)
                        ..scaleByDouble(scale, scale, 1.0, 1.0),
                      child: GestureDetector(
                        onTap: () => i == index
                            ? openItem(context, items[i],
                                queue: live ? items : null)
                            : _go(i, items.length),
                        child: _Card(
                            item: items[i],
                            landscape: live,
                            ring: focused,
                            tv: tv),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ),
      if (cur != null)
        Padding(
          padding: EdgeInsets.fromLTRB(16, 4, 16, wide ? 14 : 8),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(cur.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: wide ? 34 : 24,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.5)),
            const SizedBox(height: 2),
            Text(
              [
                switch (cur.kind) {
                  MediaKind.live => 'Live',
                  MediaKind.movie => 'Movie',
                  MediaKind.series => 'Series'
                },
                if (cur.rating != null &&
                    cur.rating!.isNotEmpty &&
                    cur.rating != '0')
                  '${cur.rating} / 10',
                '${index + 1} of ${items.length}',
              ].join('  ·  '),
              style: TextStyle(color: p.muted, fontSize: wide ? 17 : 13),
            ),
            const SizedBox(height: 10),
            Row(mainAxisSize: MainAxisSize.min, children: [
              FilledButton(
                  onPressed: () =>
                      openItem(context, cur, queue: live ? items : null),
                  child:
                      Text(cur.kind == MediaKind.series ? 'Episodes' : 'Play')),
              const SizedBox(width: 10),
              FilledButton.tonal(
                  onPressed: () => app.toggleFavorite(cur),
                  child: Text(app.isFavorite(cur) ? 'In My list' : 'My list')),
            ]),
          ]),
        ),
    ]);
  }
}

class _Card extends StatelessWidget {
  final MediaItem item;
  final bool landscape, ring, tv;
  const _Card(
      {required this.item,
      required this.landscape,
      required this.ring,
      required this.tv});

  @override
  Widget build(BuildContext context) {
    final p = LayoutPalette.of(context);
    return AspectRatio(
      aspectRatio: landscape ? 16 / 10 : 2 / 3,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 100),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
              color: ring ? (tv ? p.ring : p.accent) : Colors.transparent,
              width: 4),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withValues(alpha: 0.5),
                blurRadius: 18,
                offset: const Offset(0, 8))
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: Stack(fit: StackFit.expand, children: [
            Container(
              color: p.surfaceHi,
              child: item.poster == null
                  ? Center(
                      child: Icon(
                          item.kind == MediaKind.live
                              ? Icons.live_tv
                              : (item.kind == MediaKind.movie
                                  ? Icons.movie
                                  : Icons.tv),
                          color: p.muted,
                          size: 40))
                  : NetImage(item.poster!,
                      fit: landscape ? BoxFit.contain : BoxFit.cover,
                      fallback: () => Center(
                          child: Icon(Icons.movie, color: p.muted, size: 40))),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Container(
                padding: const EdgeInsets.fromLTRB(10, 22, 10, 10),
                decoration: const BoxDecoration(
                    gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Colors.transparent, Color(0xDD000000)])),
                child: Text(item.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontWeight: FontWeight.w700, fontSize: 14)),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}
