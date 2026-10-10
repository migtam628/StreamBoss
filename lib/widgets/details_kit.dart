import 'dart:ui' show ImageFilter;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../layouts/common.dart';
import '../layouts/ui_layout.dart';
import '../models/media.dart';
import '../services/tmdb.dart';
import '../state/app_state.dart';
import '../state/settings_state.dart';
import 'net_image.dart';
import 'tv.dart';

/// What is known about a movie or series: TMDB when a key is set, the provider for the gaps.
Future<TmdbInfo?> loadDetails(BuildContext context, MediaItem item) async {
  final key = context.read<SettingsState>().tmdbKey;
  final app = context.read<AppState>();
  final r = await Future.wait<TmdbInfo?>([
    TmdbService(key).lookup(item),
    app.providerInfo(item),
  ]);
  return mergeInfo(r[0], r[1]);
}

/// The Showcase picture: a backdrop (or the poster, blurred, when there is no backdrop) fading into the
/// page, with the title, a line of facts and an optional tagline laid over its lower edge.
class DetailsHero extends StatelessWidget {
  final String title;
  final String? backdrop, poster, tagline;
  final List<String> chips;

  /// Shown at the top left; a TV remote's Back key does the same.
  final VoidCallback? onBack;
  final List<Widget> actions;
  const DetailsHero({
    super.key,
    required this.title,
    this.backdrop,
    this.poster,
    this.tagline,
    this.chips = const [],
    this.onBack,
    this.actions = const [],
  });

  @override
  Widget build(BuildContext context) {
    final p = LayoutPalette.of(context);
    final tv = TvScope.of(context);
    final wide = MediaQuery.sizeOf(context).width >= 700 || tv;
    final h = wide ? 340.0 : 240.0;
    Widget art;
    if (backdrop != null) {
      art = NetImage(backdrop!);
    } else if (poster != null) {
      art = ImageFiltered(
        imageFilter: ImageFilter.blur(sigmaX: 28, sigmaY: 28),
        child: Transform.scale(scale: 1.4, child: NetImage(poster!)),
      );
    } else {
      art = const SizedBox.shrink();
    }
    return SizedBox(
      height: h,
      child: Stack(fit: StackFit.expand, children: [
        ColoredBox(color: p.surfaceHi),
        art,
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [p.bg.withValues(alpha: 0.15), p.bg.withValues(alpha: 0.55), p.bg],
              stops: const [0, 0.55, 1],
            ),
          ),
        ),
        if (onBack != null)
          Positioned(
            top: 8,
            left: 8,
            child: IconButton(
              tooltip: 'Back',
              icon: Icon(Icons.arrow_back, color: p.text),
              style: IconButton.styleFrom(backgroundColor: p.bg.withValues(alpha: 0.45)),
              onPressed: onBack,
            ),
          ),
        if (actions.isNotEmpty) Positioned(top: 8, right: 8, child: Row(children: actions)),
        Positioned(
          left: 20,
          right: 20,
          bottom: 14,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            Text(title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: wide ? 38 : 26, fontWeight: FontWeight.w800, color: p.text, height: 1.1)),
            if (tagline != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(tagline!, style: TextStyle(color: p.muted, fontStyle: FontStyle.italic)),
              ),
            if (chips.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 10), child: MetaChips(chips)),
          ]),
        ),
      ]),
    );
  }
}

/// The small boxed facts under a title: 2021, 1h 48m, ★ 7.8, 13+, 1080p.
class MetaChips extends StatelessWidget {
  final List<String> chips;
  const MetaChips(this.chips, {super.key});

  @override
  Widget build(BuildContext context) {
    final p = LayoutPalette.of(context);
    return Wrap(spacing: 8, runSpacing: 6, children: [
      for (final c in chips)
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
          decoration: BoxDecoration(
            color: p.wash(0.12),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(c, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: p.text)),
        ),
    ]);
  }
}

/// Section title used inside the tabs.
class DetailsHeading extends StatelessWidget {
  final String text;
  const DetailsHeading(this.text, {super.key});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(0, 18, 0, 8),
        child: Text(text.toUpperCase(),
            style: TextStyle(
                fontSize: 12, letterSpacing: 1.1, fontWeight: FontWeight.w800, color: LayoutPalette.of(context).muted)),
      );
}

/// A table of label and value pairs; rows with no value are left out.
class FactsTable extends StatelessWidget {
  final List<(String, String?)> rows;
  const FactsTable(this.rows, {super.key});

  @override
  Widget build(BuildContext context) {
    final p = LayoutPalette.of(context);
    final shown = [
      for (final r in rows)
        if (r.$2 != null && r.$2!.trim().isNotEmpty) r,
    ];
    if (shown.isEmpty) return Text('Nothing more is known about this one.', style: TextStyle(color: p.muted));
    return Column(children: [
      for (final r in shown)
        Container(
          padding: const EdgeInsets.symmetric(vertical: 9),
          decoration: BoxDecoration(border: Border(bottom: BorderSide(color: p.line))),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SizedBox(width: 130, child: Text(r.$1, style: TextStyle(color: p.muted))),
            Expanded(child: Text(r.$2!, style: TextStyle(color: p.text, fontWeight: FontWeight.w600))),
          ]),
        ),
    ]);
  }
}

/// Cast cards: a photo (or initials), the name and the part.
class PeopleWrap extends StatelessWidget {
  final List<Person> people;
  const PeopleWrap(this.people, {super.key});

  static String initials(String name) {
    final w = name.trim().split(RegExp(r'\s+')).where((e) => e.isNotEmpty).toList();
    if (w.isEmpty) return '?';
    return (w.first[0] + (w.length > 1 ? w.last[0] : '')).toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final p = LayoutPalette.of(context);
    return Wrap(spacing: 14, runSpacing: 14, children: [
      for (final c in people)
        SizedBox(
          width: 220,
          child: Row(children: [
            CircleAvatar(
              radius: 26,
              backgroundColor: p.surfaceHi,
              child: c.photo != null
                  ? ClipOval(child: SizedBox(width: 52, height: 52, child: NetImage(c.photo!)))
                  : Text(initials(c.name), style: TextStyle(color: p.text, fontWeight: FontWeight.w800)),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(c.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: p.text, fontWeight: FontWeight.w700)),
                if (c.role != null && c.role!.isNotEmpty)
                  Text(c.role!, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: p.muted, fontSize: 12)),
              ]),
            ),
          ]),
        ),
    ]);
  }
}

/// The stripe under a thumbnail or episode row that shows how far through you are.
class ProgressStripe extends StatelessWidget {
  final double value;
  const ProgressStripe(this.value, {super.key});

  @override
  Widget build(BuildContext context) {
    final p = LayoutPalette.of(context);
    return ClipRRect(
      borderRadius: BorderRadius.circular(2),
      child: LinearProgressIndicator(value: value, minHeight: 3, color: p.accent, backgroundColor: p.wash(0.15)),
    );
  }
}

/// Tab headings for a details page: a row of chips, Left and Right on a remote change tab.
class DetailTabs extends StatelessWidget {
  final List<String> labels;
  final int selected;
  final ValueChanged<int> onSelect;
  const DetailTabs({super.key, required this.labels, required this.selected, required this.onSelect});

  @override
  Widget build(BuildContext context) =>
      ChipRow(labels: labels, selected: selected, onSelect: onSelect, padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8));
}

/// A shelf of titles (More like this, Other copies): posters in a wrap that scrolls with the page.
class TitleShelf extends StatelessWidget {
  final List<MediaItem> items;
  final void Function(MediaItem) onOpen;
  final void Function(MediaItem)? onHold;
  const TitleShelf({super.key, required this.items, required this.onOpen, this.onHold});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final size = context.watch<SettingsState>().posterScale;
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 150 * size, childAspectRatio: 2 / 3, mainAxisSpacing: 12, crossAxisSpacing: 12),
      itemCount: items.length,
      itemBuilder: (_, i) => _Tile(items[i], app, onOpen, onHold),
    );
  }
}

class _Tile extends StatelessWidget {
  final MediaItem item;
  final AppState app;
  final void Function(MediaItem) open;
  final void Function(MediaItem)? hold;
  const _Tile(this.item, this.app, this.open, this.hold);

  @override
  Widget build(BuildContext context) => FocusSurface(
        radius: 10,
        semanticLabel: item.name,
        onTap: () => open(item),
        onLongPress: hold == null ? null : () => hold!(item),
        builder: (c, _) => Stack(fit: StackFit.expand, children: [
          ColoredBox(color: LayoutPalette.of(c).surfaceHi),
          if (item.poster != null) NetImage(item.poster!),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Container(
              padding: const EdgeInsets.fromLTRB(6, 14, 6, 6),
              decoration: const BoxDecoration(
                gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Colors.transparent, Colors.black87]),
              ),
              child: Text(item.name, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600)),
            ),
          ),
        ]),
      );
}
