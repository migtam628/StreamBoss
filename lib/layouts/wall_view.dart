import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/media.dart';
import '../screens/open_item.dart';
import '../services/vod_filter.dart';
import '../state/app_state.dart';
import '../state/settings_state.dart';
import '../widgets/media_tile.dart';
import '../widgets/net_image.dart';
import '../widgets/tv.dart';
import '../widgets/vod_filter_bar.dart';
import 'common.dart';
import 'ui_layout.dart';

/// Wall's Home: the whole library as one poster wall. Movies, Series and Live each have a wall; the
/// poster the cursor is on shows its details beside (or under) the wall. Zoom out to see more at once.
/// Moving across a wall never pages: it is one scroll. On a touch screen the first tap on a poster
/// selects it and the second opens it.
class WallHome extends StatefulWidget {
  const WallHome({super.key});

  @override
  State<WallHome> createState() => _WallHomeState();
}

class _WallHomeState extends State<WallHome> {
  MediaKind _kind = MediaKind.movie;
  int _zoom = 1; // 0 close, 1 normal, 2 far
  MediaItem? _sel;

  static const _extent = [190.0, 140.0, 96.0];
  static const _kinds = [(MediaKind.movie, 'Movies'), (MediaKind.series, 'Series'), (MediaKind.live, 'Live')];

  String _list(MediaKind k) => k == MediaKind.series ? 'series' : 'movie';

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final p = LayoutPalette.of(context);
    final tv = TvScope.of(context);
    final wide = tv || MediaQuery.sizeOf(context).width >= 800;
    final c = s.shown;
    final base = c.itemsFor(_kind);
    final items = _kind == MediaKind.live ? s.filterChannels(base) : s.filterVod(_list(_kind), base);
    final sel = (_sel != null && items.any((i) => i.key == _sel!.key)) ? _sel : (items.isEmpty ? null : items.first);
    final scale = context.watch<SettingsState>().posterScale;
    final live = _kind == MediaKind.live;

    final header = Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      child: Row(children: [
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(children: [
        for (final (k, label) in _kinds)
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: FocusSurface(
              radius: 20,
              semanticLabel: label,
              onTap: () => setState(() {
                _kind = k;
                _sel = null;
              }),
              builder: (_, __) => Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                color: _kind == k ? p.accent : p.wash(0.08),
                child: Text(label, style: TextStyle(fontWeight: FontWeight.w800, color: _kind == k ? p.onAccent : p.text)),
              ),
            ),
          ),
        ]))),
        IconButton(
          tooltip: 'Zoom: ${['close up', 'normal', 'zoomed out'][_zoom]}',
          icon: Icon([Icons.zoom_in, Icons.zoom_in_map, Icons.zoom_out_map][_zoom], color: p.accent),
          onPressed: () => setState(() => _zoom = (_zoom + 1) % 3),
        ),
      ]),
    );

    final wall = GridView.builder(
      padding: const EdgeInsets.all(12),
      gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: (live ? _extent[_zoom] * 1.5 : _extent[_zoom]) * scale,
        childAspectRatio: live ? 16 / 10 : 2 / 3,
        mainAxisSpacing: _zoom == 2 ? 6 : 12,
        crossAxisSpacing: _zoom == 2 ? 6 : 12,
      ),
      itemCount: items.length,
      itemBuilder: (_, i) {
        final it = items[i];
        return MediaTile(
          item: it,
          favorite: s.isFavorite(it),
          offline: live && s.isDead(it),
          onFocus: (f) {
            if (f && tv && _sel?.key != it.key) setState(() => _sel = it);
          },
          onTap: () {
            if (!tv && sel?.key != it.key) {
              setState(() => _sel = it);
            } else {
              openItem(context, it, queue: items);
            }
          },
          onLongPress: () => setState(() => _zoom = _zoom == 2 ? 1 : 2),
        );
      },
    );

    final details = sel == null ? const SizedBox.shrink() : _Details(item: sel, wide: wide, live: live, favorite: s.isFavorite(sel), onFavorite: () => s.toggleFavorite(sel));

    final bar = live ? const SizedBox.shrink() : VodFilterBar(list: _list(_kind), noun: _kind == MediaKind.movie ? 'movies' : 'series', shown: items.length);
    return Column(children: [
      header,
      bar,
      Expanded(
        child: items.isEmpty
            ? Center(child: Text(base.isEmpty ? 'Nothing here yet.' : 'No titles match the filters.', style: TextStyle(color: p.muted)))
            : wide
                ? Row(children: [Expanded(child: wall), SizedBox(width: 320, child: details)])
                : Column(children: [Expanded(child: wall), details]),
      ),
    ]);
  }
}

class _Details extends StatelessWidget {
  final MediaItem item;
  final bool wide, live, favorite;
  final VoidCallback onFavorite;
  const _Details({required this.item, required this.wide, required this.live, required this.favorite, required this.onFavorite});

  @override
  Widget build(BuildContext context) {
    final p = LayoutPalette.of(context);
    final year = yearOf(item);
    final r = ratingOf(item);
    final meta = [
      if (year != null) '$year',
      if (r > 0) '★ ${r.toStringAsFixed(1)}',
      if (live) 'Live',
    ].join('  ·  ');
    final text = Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
      Text(item.name, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: wide ? 24 : 18, fontWeight: FontWeight.w800, color: p.text)),
      if (meta.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 4), child: Text(meta, style: TextStyle(color: p.accent2, fontSize: wide ? 16 : 13))),
      if ((item.plot ?? '').isNotEmpty)
        Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(item.plot!, maxLines: wide ? 6 : 2, overflow: TextOverflow.ellipsis, style: TextStyle(color: p.muted, fontSize: wide ? 15 : 13, height: 1.35))),
    ]);
    if (!wide) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
        decoration: BoxDecoration(color: p.surface, border: Border(top: BorderSide(color: p.line))),
        child: Row(children: [
          Expanded(child: text),
          IconButton(tooltip: favorite ? 'Remove from My List' : 'Add to My List', icon: Icon(favorite ? Icons.favorite : Icons.favorite_border, color: p.accent), onPressed: onFavorite),
        ]),
      );
    }
    return Container(
      margin: const EdgeInsets.fromLTRB(0, 12, 12, 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: p.surface, border: Border.all(color: p.line), borderRadius: BorderRadius.circular(16)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(
          height: live ? 130 : 210,
          child: Center(
            child: AspectRatio(
              aspectRatio: live ? 16 / 10 : 2 / 3,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: item.poster == null
                    ? ColoredBox(color: p.surfaceHi)
                    : NetImage(item.poster!, fit: live ? BoxFit.contain : BoxFit.cover, fallback: () => ColoredBox(color: p.surfaceHi)),
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        Flexible(child: SingleChildScrollView(physics: const NeverScrollableScrollPhysics(), child: text)),
      ]),
    );
  }
}
