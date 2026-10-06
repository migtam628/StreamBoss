import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/media.dart';
import '../screens/open_item.dart';
import '../state/app_state.dart';
import '../widgets/net_image.dart';
import '../widgets/tv.dart';
import 'common.dart';
import 'shell_nav.dart';
import 'ui_layout.dart';

const _mono = 'monospace';

/// Library's frame on wide screens: a thin breadcrumb on top and the tree of screens on the left,
/// with counts. The body is whichever screen is selected.
class LibraryChrome extends StatelessWidget {
  final int index;
  final ValueChanged<int> onSelect;
  final Widget body;
  const LibraryChrome({super.key, required this.index, required this.onSelect, required this.body});

  @override
  Widget build(BuildContext context) {
    final p = LayoutPalette.of(context);
    final s = context.watch<AppState>();
    final c = s.shown;
    final counts = {1: c.live.length, 3: c.movies.length, 4: c.series.length, 0: s.recents.length};
    return Column(children: [
      Container(
        height: 46,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(color: p.surface, border: Border(bottom: BorderSide(color: p.line))),
        child: Row(children: [
          SizedBox(
            width: 204,
            child: Text('STREAMBOSS', style: TextStyle(color: p.accent, fontWeight: FontWeight.w800, letterSpacing: 2.4, fontSize: 16)),
          ),
          Text('Library', style: TextStyle(color: p.muted, fontSize: 16)),
          Icon(Icons.chevron_right, color: p.muted, size: 18),
          Text(index == 0 ? 'Home' : destLabel(UiLayout.library, index),
              style: TextStyle(color: p.text, fontWeight: FontWeight.w700, fontSize: 16)),
          const Spacer(),
          const NavClock(),
        ]),
      ),
      Expanded(
        child: Row(children: [
          Container(
            width: 220,
            decoration: BoxDecoration(color: p.surface, border: Border(right: BorderSide(color: p.line))),
            child: ListView(padding: const EdgeInsets.symmetric(vertical: 10), children: [
              const _SideHead('Library'),
              for (final i in const [0, 1, 2, 3, 4])
                _SideRow(
                    label: i == 0 ? 'Home' : destLabel(UiLayout.library, i),
                    icon: destIcon(UiLayout.library, i, selected: i == index),
                    count: i == 0 ? null : counts[i],
                    selected: i == index,
                    onTap: () => onSelect(i)),
              const SizedBox(height: 8),
              Divider(color: p.line, height: 1),
              const SizedBox(height: 8),
              const _SideHead('Tools'),
              for (final i in const [5, 6])
                _SideRow(
                    label: destLabel(UiLayout.library, i),
                    icon: destIcon(UiLayout.library, i, selected: i == index),
                    selected: i == index,
                    onTap: () => onSelect(i)),
            ]),
          ),
          Expanded(child: body),
        ]),
      ),
    ]);
  }
}

class _SideHead extends StatelessWidget {
  final String text;
  const _SideHead(this.text);

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(18, 4, 18, 8),
        child: Text(text.toUpperCase(),
            style: TextStyle(color: LayoutPalette.of(context).muted, fontSize: 13, letterSpacing: 2, fontWeight: FontWeight.w700)),
      );
}

class _SideRow extends StatelessWidget {
  final String label;
  final IconData icon;
  final int? count;
  final bool selected;
  final VoidCallback onTap;
  const _SideRow({required this.label, required this.icon, required this.selected, required this.onTap, this.count});

  @override
  Widget build(BuildContext context) {
    final p = LayoutPalette.of(context);
    return FocusSurface(
      radius: 4,
      semanticLabel: label,
      onTap: onTap,
      builder: (_, __) => Container(
        height: 42,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        color: selected ? p.accent.withValues(alpha: 0.17) : Colors.transparent,
        child: Row(children: [
          Icon(icon, size: 19, color: selected ? p.accent : p.muted),
          const SizedBox(width: 10),
          Expanded(
              child: Text(label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: selected ? p.text : p.text.withValues(alpha: 0.8), fontSize: 16, fontWeight: selected ? FontWeight.w700 : FontWeight.w500))),
          if (count != null && count! > 0)
            Text('$count', style: TextStyle(fontFamily: _mono, color: selected ? p.accent : p.muted, fontSize: 14)),
        ]),
      ),
    );
  }
}

/// Library's Home: dense rows grouped under small headings, like a media server's overview.
class LibraryHome extends StatelessWidget {
  const LibraryHome({super.key});

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final c = s.shown;
    final p = LayoutPalette.of(context);
    final wide = TvScope.of(context) || MediaQuery.sizeOf(context).width >= 800;
    final empty = s.recents.isEmpty && c.live.isEmpty && c.movies.isEmpty && c.series.isEmpty;
    if (empty) return Center(child: Text('Nothing here yet.', style: TextStyle(color: p.muted)));
    return ListView(padding: const EdgeInsets.only(bottom: 16), children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
        child: Text('Home', style: TextStyle(fontSize: wide ? 30 : 24, fontWeight: FontWeight.w800, color: p.text)),
      ),
      _Section(title: 'Continue watching', items: s.recents.take(6).toList(), wide: wide),
      _Section(title: 'Live now', items: c.live.take(8).toList(), queue: c.live, wide: wide),
      _Section(title: 'Movies', items: c.movies.take(8).toList(), wide: wide),
      _Section(title: 'Series', items: c.series.take(6).toList(), wide: wide),
    ]);
  }
}

class _Section extends StatelessWidget {
  final String title;
  final List<MediaItem> items;
  final List<MediaItem>? queue;
  final bool wide;
  const _Section({required this.title, required this.items, required this.wide, this.queue});

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox.shrink();
    final p = LayoutPalette.of(context);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 6),
        child: Row(children: [
          Text(title.toUpperCase(), style: TextStyle(fontFamily: _mono, color: p.muted, fontSize: 13, letterSpacing: 1.6)),
          const Spacer(),
          Text('${items.length}', style: TextStyle(fontFamily: _mono, color: p.accent, fontSize: 13)),
        ]),
      ),
      Divider(color: p.line, height: 1),
      for (final it in items) _Row(item: it, queue: queue, wide: wide),
    ]);
  }
}

class _Row extends StatelessWidget {
  final MediaItem item;
  final List<MediaItem>? queue;
  final bool wide;
  const _Row({required this.item, required this.wide, this.queue});

  @override
  Widget build(BuildContext context) {
    final p = LayoutPalette.of(context);
    final s = context.watch<AppState>();
    final r = s.resumeFor(item);
    final kind = switch (item.kind) { MediaKind.live => 'LIVE', MediaKind.movie => 'MOVIE', MediaKind.series => 'SERIES' };
    final hasRating = item.rating != null && item.rating!.isNotEmpty && item.rating != '0';
    return FocusSurface(
      radius: 0,
      semanticLabel: item.name,
      onTap: () => openItem(context, item, queue: queue),
      onLongPress: () => s.toggleFavorite(item),
      builder: (_, focused) => Container(
        height: 58,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        decoration: BoxDecoration(
            color: focused ? p.accent.withValues(alpha: 0.14) : Colors.transparent,
            border: Border(bottom: BorderSide(color: p.line.withValues(alpha: 0.6)))),
        child: Row(children: [
          Container(
            width: 34,
            height: 44,
            decoration: BoxDecoration(color: p.surfaceHi, borderRadius: BorderRadius.circular(3)),
            clipBehavior: Clip.antiAlias,
            child: item.poster == null
                ? Icon(item.kind == MediaKind.live ? Icons.live_tv : Icons.movie, size: 18, color: p.muted)
                : NetImage(item.poster!,
                    fit: item.kind == MediaKind.live ? BoxFit.contain : BoxFit.cover,
                    fallback: () => Icon(Icons.movie, size: 18, color: p.muted)),
          ),
          const SizedBox(width: 14),
          Expanded(
              child: Text(item.name,
                  maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: p.text, fontSize: 17, fontWeight: FontWeight.w600))),
          if (wide) ...[
            SizedBox(width: 90, child: Text(kind, style: TextStyle(fontFamily: _mono, color: p.muted, fontSize: 13))),
            SizedBox(width: 70, child: Text(hasRating ? '★ ${item.rating}' : '', style: TextStyle(fontFamily: _mono, color: p.muted, fontSize: 13))),
          ],
          SizedBox(
            width: wide ? 120 : 84,
            child: Text(r == null ? '' : '${r.inMinutes} min in',
                textAlign: TextAlign.right, style: TextStyle(fontFamily: _mono, color: p.accent2, fontSize: 13)),
          ),
        ]),
      ),
    );
  }
}
