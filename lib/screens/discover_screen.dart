import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../l10n/l10n.dart';
import '../layouts/ui_layout.dart';
import '../models/media.dart';
import '../services/discover_logic.dart';
import '../services/tmdb.dart';
import '../state/app_state.dart';
import '../widgets/net_image.dart';
import 'open_item.dart';

/// What is popular right now, from TMDB, each title marked with whether the library has it. A title the library
/// has opens like any other; one it does not has can be read about.
class DiscoverScreen extends StatefulWidget {
  const DiscoverScreen({super.key});

  @override
  State<DiscoverScreen> createState() => _DiscoverScreenState();
}

class _DiscoverScreenState extends State<DiscoverScreen> {
  Future<List<List<DiscoverTitle>?>>? _rows;
  bool _mine = false;

  Future<List<List<DiscoverTitle>?>> _load() {
    final tmdb = context.read<AppState>().tmdb();
    return Future.wait([
      for (final r in discoverRows) tmdb.discoverList(r.path, tv: r.tv),
    ]);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final hasKey = context.read<AppState>().tmdb().apiKey.isNotEmpty;
    if (hasKey) _rows ??= _load();
  }

  @override
  Widget build(BuildContext context) {
    final p = LayoutPalette.of(context);
    final app = context.watch<AppState>();
    final hasKey = app.tmdb().apiKey.isNotEmpty;
    return Scaffold(
      backgroundColor: p.bg,
      appBar: AppBar(
        backgroundColor: p.bg,
        foregroundColor: p.text,
        title: Text(tr('Discover')),
        actions: [
          if (hasKey)
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: FilterChip(
                label: Text(tr('Only what I have')),
                selected: _mine,
                onSelected: (v) => setState(() => _mine = v),
              ),
            ),
        ],
      ),
      body: !hasKey
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                    tr('Discover needs a TMDB key. Add yours in Settings > Network & metadata.'),
                    textAlign: TextAlign.center,
                    style: TextStyle(color: p.muted, fontSize: 15)),
              ),
            )
          : FutureBuilder<List<List<DiscoverTitle>?>>(
              future: _rows,
              builder: (context, snap) {
                if (snap.connectionState != ConnectionState.done) {
                  return const Center(child: CircularProgressIndicator());
                }
                final rows = snap.data ?? const [];
                if (rows.isEmpty || rows.every((r) => r == null)) {
                  return Center(
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      Text(tr('Could not load TMDB.'),
                          style: TextStyle(color: p.muted)),
                      TextButton(
                          onPressed: () => setState(() => _rows = _load()),
                          child: Text(tr('Try again'))),
                    ]),
                  );
                }
                final matcher =
                    LibraryMatcher(app.shown.movies, app.shown.series);
                return ListView(
                  padding: const EdgeInsets.only(bottom: 32),
                  children: [
                    for (var i = 0; i < rows.length; i++)
                      if (rows[i] != null)
                        _Row(
                          title: tr(discoverRows[i].title),
                          titles: rows[i]!,
                          matcher: matcher,
                          onlyMine: _mine,
                        ),
                  ],
                );
              },
            ),
    );
  }
}

class _Row extends StatelessWidget {
  final String title;
  final List<DiscoverTitle> titles;
  final LibraryMatcher matcher;
  final bool onlyMine;
  const _Row({
    required this.title,
    required this.titles,
    required this.matcher,
    required this.onlyMine,
  });

  @override
  Widget build(BuildContext context) {
    final p = LayoutPalette.of(context);
    final cards = <Widget>[];
    for (final t in titles) {
      final mine = matcher.find(t);
      if (onlyMine && mine == null) continue;
      cards.add(_Card(title: t, mine: mine));
    }
    if (cards.isEmpty) return const SizedBox.shrink();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 18, 16, 8),
        child: Text(title,
            style: TextStyle(
                color: p.text, fontSize: 18, fontWeight: FontWeight.w800)),
      ),
      SizedBox(
        height: 230,
        child: ListView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          children: cards,
        ),
      ),
    ]);
  }
}

class _Card extends StatelessWidget {
  final DiscoverTitle title;
  final MediaItem? mine;
  const _Card({required this.title, required this.mine});

  @override
  Widget build(BuildContext context) {
    final p = LayoutPalette.of(context);
    final have = mine != null;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: SizedBox(
        width: 132,
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: () => have ? openItem(context, mine!) : _about(context),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: SizedBox(
                width: 132,
                height: 190,
                child: Stack(fit: StackFit.expand, children: [
                  ColoredBox(color: p.surfaceHi),
                  if (title.poster != null)
                    Opacity(
                        opacity: have ? 1 : 0.45,
                        child: NetImage(title.poster!, decodeWidth: 300)),
                  if (have)
                    Positioned(
                      left: 6,
                      top: 6,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                            color: p.accent,
                            borderRadius: BorderRadius.circular(5)),
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          const Icon(Icons.check,
                              size: 12, color: Colors.white),
                          const SizedBox(width: 3),
                          Text(tr('In your library'),
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700)),
                        ]),
                      ),
                    ),
                ]),
              ),
            ),
            const SizedBox(height: 6),
            Text(title.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    color: have ? p.text : p.muted,
                    fontWeight: FontWeight.w700,
                    fontSize: 13)),
          ]),
        ),
      ),
    );
  }

  void _about(BuildContext context) {
    final p = LayoutPalette.of(context);
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: p.surface,
      isScrollControlled: true,
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                    [
                      title.title,
                      if (title.year != null) '(${title.year})',
                    ].join(' '),
                    style: TextStyle(
                        color: p.text,
                        fontSize: 20,
                        fontWeight: FontWeight.w800)),
                if (title.rating != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text('★ ${title.rating!.toStringAsFixed(1)}',
                        style: TextStyle(color: p.muted)),
                  ),
                const SizedBox(height: 10),
                Text(
                    title.overview.isEmpty
                        ? tr('No description from your provider yet.')
                        : title.overview,
                    style: TextStyle(color: p.text, height: 1.45)),
                const SizedBox(height: 12),
                Text(tr('Not in your library'),
                    style:
                        TextStyle(color: p.muted, fontWeight: FontWeight.w700)),
              ]),
        ),
      ),
    );
  }
}
