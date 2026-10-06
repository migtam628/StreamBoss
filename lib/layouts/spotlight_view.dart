import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/media.dart';
import '../screens/open_item.dart';
import '../state/app_state.dart';
import '../state/settings_state.dart';
import '../widgets/media_tile.dart';
import '../widgets/tv.dart';
import 'common.dart';
import 'shell_nav.dart';
import 'ui_layout.dart';

/// Spotlight: chips along the top pick a section; below, a poster grid. On wide screens the
/// title you are on gets a details panel on the left; on a phone a search pill sits on top and
/// a resume bar above the navigation.
class SpotlightView extends StatefulWidget {
  /// (chip label, items) pairs. The first is shown at the start.
  final List<(String, List<MediaItem>)> sections;
  final bool showResume;
  const SpotlightView(
      {super.key, required this.sections, this.showResume = false});

  @override
  State<SpotlightView> createState() => _SpotlightViewState();
}

class _SpotlightViewState extends State<SpotlightView> {
  int _sec = 0;
  MediaItem? _focused;

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final size = context.watch<SettingsState>().posterScale;
    final tv = TvScope.of(context);
    final wide = tv || MediaQuery.sizeOf(context).width >= 800;
    final secs = widget.sections;
    if (secs.isEmpty || secs.every((e) => e.$2.isEmpty)) {
      return Center(
          child: Text('Nothing here yet.',
              style: TextStyle(color: LayoutPalette.of(context).muted)));
    }
    final sec = _sec.clamp(0, secs.length - 1).toInt();
    final items = secs[sec].$2;
    final live =
        items.isNotEmpty && items.every((e) => e.kind == MediaKind.live);
    final shown = _focused != null && items.contains(_focused)
        ? _focused!
        : (items.isNotEmpty ? items.first : null);

    final chips = ChipRow(
      labels: [for (final e in secs) e.$1],
      selected: sec,
      onSelect: (i) => setState(() {
        _sec = i;
        _focused = null;
      }),
    );

    Widget grid(SliverGridDelegate d) => GridView.builder(
          padding: EdgeInsets.fromLTRB(wide ? 12 : 16, 10, wide ? 12 : 16, 12),
          gridDelegate: d,
          itemCount: items.length,
          itemBuilder: (_, i) {
            final it = items[i];
            return MediaTile(
              item: it,
              favorite: s.isFavorite(it),
              onFocus: (f) {
                if (f && _focused != it) setState(() => _focused = it);
              },
              onTap: () => openItem(context, it, queue: live ? items : null),
              onLongPress: () => s.toggleFavorite(it),
            );
          },
        );

    if (wide) {
      return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(
            width: 380,
            child: shown == null
                ? const SizedBox.shrink()
                : _Details(item: shown)),
        Expanded(
          child: Column(children: [
            chips,
            Expanded(
              child: grid(SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: (live ? 210 : 150) * size,
                childAspectRatio: live ? 16 / 10 : 2 / 3,
                mainAxisSpacing: 18,
                crossAxisSpacing: 14,
              )),
            ),
          ]),
        ),
      ]);
    }

    final resume =
        widget.showResume && s.recents.isNotEmpty ? s.recents.first : null;
    return Stack(children: [
      Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: FocusSurface(
            radius: 28,
            semanticLabel: 'Search',
            onTap: () => ShellNav.maybeOf(context)?.select(5),
            builder: (ctx, _) => Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              color: LayoutPalette.of(context).wash(0.10),
              child: Row(children: [
                Icon(Icons.search, color: LayoutPalette.of(ctx).muted),
                const SizedBox(width: 10),
                Expanded(
                    child: Text('Search movies, series, channels',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: LayoutPalette.of(ctx).muted))),
              ]),
            ),
          ),
        ),
        chips,
        Expanded(
          child: grid(SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: (live ? 260 : 190) * size,
            childAspectRatio: live ? 16 / 10 : 2 / 3,
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
          )),
        ),
        if (resume != null) const SizedBox(height: 64),
      ]),
      if (resume != null)
        Positioned(
            left: 12, right: 12, bottom: 8, child: _ResumeBar(item: resume)),
    ]);
  }
}

/// The focused title's details, on the left in Spotlight.
class _Details extends StatelessWidget {
  final MediaItem item;
  const _Details({required this.item});

  @override
  Widget build(BuildContext context) {
    final p = LayoutPalette.of(context);
    final s = context.watch<AppState>();
    final fav = s.isFavorite(item);
    final kind = switch (item.kind) {
      MediaKind.live => 'Live',
      MediaKind.movie => 'Movie',
      MediaKind.series => 'Series'
    };
    final resume = s.resumeFor(item);
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 12, 16, 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Eyebrow(kind),
        const SizedBox(height: 8),
        Text(item.name,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
                fontSize: 40,
                height: 1.0,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.8)),
        const SizedBox(height: 12),
        Wrap(spacing: 8, runSpacing: 6, children: [
          if (item.rating != null &&
              item.rating!.isNotEmpty &&
              item.rating != '0')
            _pill(context, '★ ${item.rating}'),
          if (resume != null) _pill(context, 'Resume ${resume.inMinutes} min'),
        ]),
        const SizedBox(height: 12),
        Text(
          item.plot != null && item.plot!.isNotEmpty
              ? item.plot!
              : 'Press OK to open details.',
          maxLines: 5,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
              color: p.text.withValues(alpha: 0.82),
              fontSize: 17,
              height: 1.35),
        ),
        const Spacer(),
        Row(children: [
          FilledButton(
              onPressed: () => openItem(context, item),
              child: Text(item.kind == MediaKind.series ? 'Episodes' : 'Play')),
          const SizedBox(width: 10),
          FilledButton.tonal(
              onPressed: () => s.toggleFavorite(item),
              child: Text(fav ? 'In My list' : 'My list')),
        ]),
      ]),
    );
  }

  Widget _pill(BuildContext context, String t) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
        decoration: BoxDecoration(
            color: LayoutPalette.of(context).wash(0.12),
            borderRadius: BorderRadius.circular(20)),
        child: Text(t, style: const TextStyle(fontSize: 14)),
      );
}

/// Phone: the last thing you watched, one tap from playing.
class _ResumeBar extends StatelessWidget {
  final MediaItem item;
  const _ResumeBar({required this.item});

  @override
  Widget build(BuildContext context) {
    final p = LayoutPalette.of(context);
    final left = context.read<AppState>().resumeFor(item);
    return FocusSurface(
      radius: 16,
      semanticLabel: 'Resume ${item.name}',
      onTap: () => openItem(context, item),
      builder: (_, __) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        color: p.surfaceHi,
        child: Row(children: [
          Icon(Icons.play_circle_fill, color: p.accent, size: 32),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(item.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w700)),
                  Text(
                      left == null
                          ? 'Continue watching'
                          : 'Resume from ${left.inMinutes} min',
                      style: TextStyle(color: p.muted, fontSize: 13)),
                ]),
          ),
        ]),
      ),
    );
  }
}
