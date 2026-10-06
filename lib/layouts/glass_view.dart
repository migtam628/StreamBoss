import 'dart:ui' show ImageFilter;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/media.dart';
import '../screens/open_item.dart';
import '../state/app_state.dart';
import '../widgets/net_image.dart';
import '../widgets/tv.dart';
import 'common.dart';
import 'home_views.dart';
import 'shell_nav.dart';
import 'ui_layout.dart';

/// Glass sits on a soft, colorful backdrop of overlapping glows. It is plain gradients (no blur
/// filter), so it costs almost nothing to draw.
class GlassBackdrop extends StatelessWidget {
  final Widget child;
  const GlassBackdrop({super.key, required this.child});

  @override
  Widget build(BuildContext context) => DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF0A4A5A), Color(0xFF1B3A8A), Color(0xFF2D1F6B)],
              stops: [0.0, 0.55, 1.0]),
        ),
        child: DecoratedBox(
          decoration: const BoxDecoration(
            gradient: RadialGradient(
                center: Alignment(-0.9, -0.8),
                radius: 0.9,
                colors: [Color(0xB31EC8C4), Color(0x001EC8C4)]),
          ),
          child: DecoratedBox(
            decoration: const BoxDecoration(
              gradient: RadialGradient(
                  center: Alignment(0.95, 0.95),
                  radius: 0.9,
                  colors: [Color(0x73FF786E), Color(0x00FF786E)]),
            ),
            child: DecoratedBox(
              decoration: const BoxDecoration(
                gradient: RadialGradient(
                    center: Alignment(0.1, 0.0),
                    radius: 0.45,
                    colors: [Color(0x40FFAA78), Color(0x00FFAA78)]),
              ),
              child: child,
            ),
          ),
        ),
      );
}

/// A frosted panel: a translucent fill with a light edge. Off a TV it also blurs what is behind it;
/// on a TV (weak GPUs) the fill alone does the job.
class GlassPanel extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;
  const GlassPanel({super.key, required this.child, this.padding = const EdgeInsets.all(18), this.radius = 24});

  @override
  Widget build(BuildContext context) {
    final tv = TvScope.of(context);
    final box = Container(
      padding: padding,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Colors.white.withValues(alpha: 0.24), Colors.white.withValues(alpha: 0.09)]),
        border: Border.all(color: Colors.white.withValues(alpha: 0.30)),
      ),
      child: child,
    );
    if (tv) return box;
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: BackdropFilter(filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14), child: box),
    );
  }
}

/// The floating dock on wide screens: every screen as a small icon with its name.
class GlassDock extends StatelessWidget {
  final int index;
  final ValueChanged<int> onSelect;
  final UiLayout layout;
  const GlassDock({super.key, required this.index, required this.onSelect, required this.layout});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: GlassPanel(
        radius: 40,
        padding: const EdgeInsets.all(6),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          for (var i = 0; i < kDests.length; i++)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: NavTab(
                label: destLabel(layout, i),
                icon: destIcon(layout, i, selected: i == index),
                selected: i == index,
                pill: true,
                onTap: () => onSelect(i),
              ),
            ),
        ]),
      ),
    );
  }
}

/// Glass's Home: a frosted feature panel, then what is live and what you were watching on panels of
/// their own, then the usual shelves.
class GlassHome extends StatelessWidget {
  const GlassHome({super.key});

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final c = s.shown;
    final wide = TvScope.of(context) || MediaQuery.sizeOf(context).width >= 800;
    final resume = s.recents.isNotEmpty ? s.recents.first : null;
    final feature = resume ?? (c.movies.isNotEmpty ? c.movies.first : (c.live.isNotEmpty ? c.live.first : null));
    return ListView(padding: const EdgeInsets.fromLTRB(0, 12, 0, 16), children: [
      if (feature != null) _Hero(item: feature, resuming: resume != null, wide: wide),
      _Strip(title: 'Live now', items: c.live.take(12).toList(), queue: c.live),
      _Strip(title: 'Continue watching', items: s.recents.take(12).toList()),
      Shelf(title: 'My list', items: s.favoriteItems),
      Shelf(title: 'Movies', items: c.movies.take(30).toList()),
      Shelf(title: 'Series', items: c.series.take(30).toList()),
    ]);
  }
}

class _Hero extends StatelessWidget {
  final MediaItem item;
  final bool resuming, wide;
  const _Hero({required this.item, required this.resuming, required this.wide});

  @override
  Widget build(BuildContext context) {
    final p = LayoutPalette.of(context);
    final s = context.watch<AppState>();
    final tv = TvScope.of(context);
    final fav = s.isFavorite(item);
    final art = AspectRatio(
      aspectRatio: wide ? 2 / 3 : 16 / 9,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: Container(
          decoration: BoxDecoration(
              gradient: LinearGradient(
                  begin: Alignment.topRight,
                  end: Alignment.bottomLeft,
                  colors: [p.accent2, const Color(0xFF2D1F6B)])),
          child: item.poster != null && item.kind != MediaKind.live
              ? NetImage(item.poster!, fit: BoxFit.cover, fallback: () => const SizedBox.shrink())
              : null,
        ),
      ),
    );
    final copy = Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
      Eyebrow(resuming ? 'Pick up where you left off' : 'Featured', color: p.accent),
      const SizedBox(height: 6),
      Text(item.name,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(fontSize: wide ? (tv ? 42 : 34) : 26, height: 1.02, fontWeight: FontWeight.w800, letterSpacing: -0.5)),
      const SizedBox(height: 8),
      Text(
          [
            item.kind == MediaKind.live ? 'Live' : (item.kind == MediaKind.series ? 'Series' : 'Movie'),
            if (item.rating != null && item.rating!.isNotEmpty && item.rating != '0') '★ ${item.rating}',
          ].join('  ·  '),
          style: TextStyle(color: p.muted, fontSize: wide ? 17 : 14)),
      if (wide && item.plot != null && item.plot!.isNotEmpty) ...[
        const SizedBox(height: 6),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Text(item.plot!,
              maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(color: p.text.withValues(alpha: 0.9), fontSize: 16, height: 1.35)),
        ),
      ],
      const SizedBox(height: 14),
      Wrap(spacing: 10, runSpacing: 8, children: [
        FilledButton.icon(
          autofocus: tv,
          onPressed: () => openItem(context, item),
          icon: const Icon(Icons.play_arrow),
          label: const Text('Play'),
        ),
        FilledButton.tonalIcon(
          onPressed: () => s.toggleFavorite(item),
          style: FilledButton.styleFrom(backgroundColor: Colors.white.withValues(alpha: 0.2), foregroundColor: p.text),
          icon: Icon(fav ? Icons.check : Icons.add),
          label: Text(fav ? 'In My list' : 'My list'),
        ),
      ]),
    ]);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: GlassPanel(
        padding: EdgeInsets.all(wide ? 22 : 16),
        child: wide
            ? SizedBox(
                height: tv ? 260 : 240,
                child: Row(children: [
                  Expanded(child: Align(alignment: Alignment.centerLeft, child: copy)),
                  const SizedBox(width: 20),
                  art,
                ]),
              )
            : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [art, const SizedBox(height: 12), copy]),
      ),
    );
  }
}

/// A frosted panel holding a row of chips, one per title or channel.
class _Strip extends StatelessWidget {
  final String title;
  final List<MediaItem> items;
  final List<MediaItem>? queue;
  const _Strip({required this.title, required this.items, this.queue});

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox.shrink();
    final p = LayoutPalette.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: GlassPanel(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        radius: 22,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
          const SizedBox(height: 10),
          SizedBox(
            height: 52,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: items.length,
              separatorBuilder: (_, __) => const SizedBox(width: 10),
              itemBuilder: (_, i) => FocusSurface(
                radius: 26,
                semanticLabel: items[i].name,
                onTap: () => openItem(context, items[i], queue: queue),
                builder: (_, __) => Container(
                  color: Colors.white.withValues(alpha: 0.16),
                  padding: const EdgeInsets.symmetric(horizontal: 18),
                  alignment: Alignment.center,
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                            color: items[i].kind == MediaKind.live ? p.accent : p.accent2, shape: BoxShape.circle)),
                    const SizedBox(width: 10),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 220),
                      child: Text(items[i].name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600)),
                    ),
                  ]),
                ),
              ),
            ),
          ),
        ]),
      ),
    );
  }
}
