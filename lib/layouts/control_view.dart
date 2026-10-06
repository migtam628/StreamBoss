import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/media.dart';
import '../screens/open_item.dart';
import '../services/time_format.dart';
import '../services/xtream_client.dart';
import '../state/app_state.dart';
import '../state/settings_state.dart';
import '../widgets/media_tile.dart';
import '../widgets/net_image.dart';
import '../widgets/tv.dart';
import 'common.dart';
import 'ui_layout.dart';

/// Control Room: categories on the left, the list in the middle, details of the highlighted
/// item on the right (wide screens). Live shows a numbered channel list with what is on now;
/// movies and series show posters. On a phone the categories become chips above the list.
class ControlView extends StatefulWidget {
  final MediaKind kind;
  final Catalog catalog;
  const ControlView({super.key, required this.kind, required this.catalog});

  @override
  State<ControlView> createState() => _ControlViewState();
}

class _ControlViewState extends State<ControlView> {
  String? _cat;
  MediaItem? _focused;
  final _epg = <String, Future<List<EpgEntry>>>{};

  Future<List<EpgEntry>> _epgFor(MediaItem ch) => _epg.putIfAbsent(ch.id,
      () => context.read<AppState>().epg(ch).catchError((_) => <EpgEntry>[]));

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final size = context.watch<SettingsState>().posterScale;
    final p = LayoutPalette.of(context);
    final tv = TvScope.of(context);
    final wide = tv || MediaQuery.sizeOf(context).width >= 800;
    final cats = widget.catalog.categoriesFor(widget.kind);
    final all = widget.catalog.itemsFor(widget.kind);
    final items =
        _cat == null ? all : all.where((i) => i.categoryId == _cat).toList();
    final live = widget.kind == MediaKind.live;
    if (all.isEmpty) {
      return Center(
          child: Text('Nothing here yet.', style: TextStyle(color: p.muted)));
    }
    final shown = _focused != null && items.contains(_focused)
        ? _focused
        : (items.isNotEmpty ? items.first : null);

    void pick(String? id) => setState(() {
          _cat = id;
          _focused = null;
        });

    final Widget list = live
        ? ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            itemCount: items.length,
            itemBuilder: (_, i) => _ChannelRow(
              number: i + 1,
              item: items[i],
              epg: _epgFor(items[i]),
              compact: !wide,
              onFocus: (f) {
                if (f && _focused != items[i]) {
                  setState(() => _focused = items[i]);
                }
              },
              onTap: () => openItem(context, items[i], queue: items),
              onLongPress: () => s.toggleFavorite(items[i]),
              favorite: s.isFavorite(items[i]),
            ),
          )
        : GridView.builder(
            padding: const EdgeInsets.all(12),
            gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 150 * size,
              childAspectRatio: 2 / 3,
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
            ),
            itemCount: items.length,
            itemBuilder: (_, i) => MediaTile(
              item: items[i],
              favorite: s.isFavorite(items[i]),
              onFocus: (f) {
                if (f && _focused != items[i]) {
                  setState(() => _focused = items[i]);
                }
              },
              onTap: () => openItem(context, items[i], queue: items),
              onLongPress: () => s.toggleFavorite(items[i]),
            ),
          );

    if (!wide) {
      return Column(children: [
        ChipRow(
          labels: ['All', for (final c in cats) c.name],
          selected: _cat == null ? 0 : cats.indexWhere((c) => c.id == _cat) + 1,
          onSelect: (i) => pick(i == 0 ? null : cats[i - 1].id),
        ),
        Expanded(child: list),
      ]);
    }

    return Row(children: [
      SizedBox(
        width: 210,
        child: Container(
          decoration:
              BoxDecoration(border: Border(right: BorderSide(color: p.line))),
          child: ListView(padding: const EdgeInsets.all(8), children: [
            _CatRow(
                label: 'All',
                count: all.length,
                selected: _cat == null,
                onTap: () => pick(null)),
            for (final c in cats)
              _CatRow(
                label: c.name,
                count: all.where((i) => i.categoryId == c.id).length,
                selected: _cat == c.id,
                onTap: () => pick(c.id),
              ),
          ]),
        ),
      ),
      Expanded(child: list),
      SizedBox(
        width: 340,
        child: Container(
          decoration:
              BoxDecoration(border: Border(left: BorderSide(color: p.line))),
          child: shown == null
              ? const SizedBox.shrink()
              : _PreviewPane(item: shown, epg: live ? _epgFor(shown) : null),
        ),
      ),
    ]);
  }
}

class _CatRow extends StatelessWidget {
  final String label;
  final int count;
  final bool selected;
  final VoidCallback onTap;
  const _CatRow(
      {required this.label,
      required this.count,
      required this.selected,
      required this.onTap});

  @override
  Widget build(BuildContext context) {
    final p = LayoutPalette.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: FocusSurface(
        radius: 10,
        semanticLabel: label,
        onTap: onTap,
        builder: (_, __) => Container(
          color: selected ? p.surfaceHi : Colors.transparent,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(children: [
            Expanded(
              child: Text(label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      color: selected ? p.text : p.text.withValues(alpha: 0.75),
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                      fontSize: 16)),
            ),
            Text('$count',
                style: TextStyle(
                    color: p.muted,
                    fontSize: 13,
                    fontFeatures: const [FontFeature.tabularFigures()])),
          ]),
        ),
      ),
    );
  }
}

/// A channel in the list: number, logo, name, what is on and how far through it is.
class _ChannelRow extends StatelessWidget {
  final int number;
  final MediaItem item;
  final Future<List<EpgEntry>> epg;
  final bool compact, favorite;
  final ValueChanged<bool> onFocus;
  final VoidCallback onTap, onLongPress;
  const _ChannelRow({
    required this.number,
    required this.item,
    required this.epg,
    required this.compact,
    required this.favorite,
    required this.onFocus,
    required this.onTap,
    required this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final p = LayoutPalette.of(context);
    final logo = compact ? 38.0 : 46.0;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: FocusSurface(
        radius: 12,
        semanticLabel: item.name,
        onFocus: onFocus,
        onTap: onTap,
        onLongPress: onLongPress,
        builder: (_, focused) => Container(
          color: focused ? p.surfaceHi : Colors.transparent,
          padding:
              EdgeInsets.symmetric(horizontal: 10, vertical: compact ? 7 : 8),
          child: Row(children: [
            SizedBox(
              width: compact ? 30 : 40,
              child: Text('$number',
                  style: TextStyle(
                      color: p.muted,
                      fontSize: 14,
                      fontFeatures: const [FontFeature.tabularFigures()])),
            ),
            Container(
              width: logo,
              height: logo,
              decoration: BoxDecoration(
                  color: p.surfaceHi, borderRadius: BorderRadius.circular(8)),
              clipBehavior: Clip.antiAlias,
              child: item.poster == null
                  ? Icon(Icons.live_tv, color: p.muted, size: 20)
                  : NetImage(item.poster!,
                      fit: BoxFit.contain,
                      fallback: () =>
                          Icon(Icons.live_tv, color: p.muted, size: 20)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: FutureBuilder<List<EpgEntry>>(
                future: epg,
                builder: (_, snap) {
                  final now = (snap.data ?? const <EpgEntry>[])
                      .where((e) => e.isNow)
                      .firstOrNull;
                  return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(children: [
                          Flexible(
                              child: Text(item.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w700,
                                      fontSize: 16))),
                          if (favorite)
                            Padding(
                                padding: const EdgeInsets.only(left: 6),
                                child: Icon(Icons.favorite,
                                    size: 14, color: p.accent2)),
                        ]),
                        Text(
                            now?.title ??
                                (snap.connectionState == ConnectionState.done
                                    ? 'No guide data'
                                    : ' '),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(color: p.muted, fontSize: 14)),
                        if (now != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(4),
                              child: LinearProgressIndicator(
                                value: _progress(now),
                                minHeight: 4,
                                backgroundColor:
                                    Colors.white.withValues(alpha: 0.12),
                                valueColor: AlwaysStoppedAnimation(p.accent),
                              ),
                            ),
                          ),
                      ]);
                },
              ),
            ),
            if (!compact)
              FutureBuilder<List<EpgEntry>>(
                future: epg,
                builder: (_, snap) {
                  final now = (snap.data ?? const <EpgEntry>[])
                      .where((e) => e.isNow)
                      .firstOrNull;
                  return SizedBox(
                    width: 70,
                    child: Text(now == null ? '' : _left(now),
                        textAlign: TextAlign.right,
                        style: TextStyle(color: p.muted, fontSize: 13)),
                  );
                },
              ),
          ]),
        ),
      ),
    );
  }
}

double _progress(EpgEntry e) {
  final total = e.end.difference(e.start).inSeconds;
  if (total <= 0) return 0;
  return (DateTime.now().difference(e.start).inSeconds / total).clamp(0.0, 1.0);
}

String _left(EpgEntry e) {
  final m = e.end.difference(DateTime.now()).inMinutes;
  if (m < 1) return 'ending';
  return m >= 60 ? '${m ~/ 60}h ${m % 60}m left' : '$m min left';
}

/// Details of the highlighted channel or title.
class _PreviewPane extends StatelessWidget {
  final MediaItem item;
  final Future<List<EpgEntry>>? epg;
  const _PreviewPane({required this.item, this.epg});

  @override
  Widget build(BuildContext context) {
    final p = LayoutPalette.of(context);
    final use24h = context.read<SettingsState>().use24h;
    final s = context.watch<AppState>();
    final live = item.kind == MediaKind.live;
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        AspectRatio(
          aspectRatio: live ? 16 / 9 : 16 / 9,
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              gradient: LinearGradient(
                  colors: [p.surfaceHi, p.bg],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight),
            ),
            clipBehavior: Clip.antiAlias,
            child: Stack(fit: StackFit.expand, children: [
              if (item.poster != null)
                Padding(
                  padding: EdgeInsets.all(live ? 18 : 0),
                  child: NetImage(item.poster!,
                      fit: live ? BoxFit.contain : BoxFit.cover,
                      fallback: () => const SizedBox.shrink()),
                ),
              if (live)
                Positioned(
                  left: 10,
                  top: 10,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                        color: const Color(0xFFE5484D),
                        borderRadius: BorderRadius.circular(5)),
                    child: const Text('LIVE',
                        style: TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 12,
                            letterSpacing: 1)),
                  ),
                ),
            ]),
          ),
        ),
        const SizedBox(height: 12),
        Text(item.name,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
        const SizedBox(height: 6),
        if (!live)
          Expanded(
            child: Text(
              [
                if (item.rating != null &&
                    item.rating!.isNotEmpty &&
                    item.rating != '0')
                  '★ ${item.rating}',
                if (item.plot != null && item.plot!.isNotEmpty) item.plot!,
              ].join('\n\n'),
              overflow: TextOverflow.fade,
              style: TextStyle(color: p.muted, fontSize: 15, height: 1.35),
            ),
          )
        else
          Expanded(
            child: FutureBuilder<List<EpgEntry>>(
              future: epg,
              builder: (_, snap) {
                final list = snap.data ?? const <EpgEntry>[];
                final now = list.where((e) => e.isNow).firstOrNull;
                final next = list
                    .where((e) => e.start.isAfter(DateTime.now()))
                    .take(3)
                    .toList();
                if (now == null && next.isEmpty) {
                  return Text(
                      snap.connectionState == ConnectionState.done
                          ? 'No guide data for this channel.'
                          : '',
                      style: TextStyle(color: p.muted));
                }
                return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (now != null) ...[
                        Text(
                            '${fmtTime(now.start, use24h: use24h)} – ${fmtTime(now.end, use24h: use24h)}',
                            style: TextStyle(
                                color: p.accent,
                                fontWeight: FontWeight.w700,
                                fontSize: 14)),
                        const SizedBox(height: 2),
                        Text(now.title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 16)),
                        const SizedBox(height: 6),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: LinearProgressIndicator(
                              value: _progress(now),
                              minHeight: 4,
                              backgroundColor: Colors.white12,
                              valueColor: AlwaysStoppedAnimation(p.accent)),
                        ),
                      ],
                      const Spacer(),
                      for (final n in next)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Row(children: [
                            Text(fmtTime(n.start, use24h: use24h),
                                style: TextStyle(
                                    color: p.muted,
                                    fontSize: 14,
                                    fontFeatures: const [
                                      FontFeature.tabularFigures()
                                    ])),
                            const SizedBox(width: 10),
                            Expanded(
                                child: Text(n.title,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(fontSize: 14))),
                          ]),
                        ),
                    ]);
              },
            ),
          ),
        const SizedBox(height: 8),
        Row(children: [
          FilledButton(
              onPressed: () => openItem(context, item),
              child: Text(live
                  ? 'Watch'
                  : (item.kind == MediaKind.series ? 'Episodes' : 'Play'))),
          const SizedBox(width: 8),
          FilledButton.tonal(
              onPressed: () => s.toggleFavorite(item),
              child: Icon(
                  s.isFavorite(item) ? Icons.favorite : Icons.favorite_border,
                  size: 20)),
        ]),
      ]),
    );
  }
}
