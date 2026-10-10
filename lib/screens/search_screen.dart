import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../layouts/common.dart';
import '../layouts/ui_layout.dart';
import '../models/media.dart';
import '../services/languages.dart';
import '../services/search.dart';
import '../state/app_state.dart';
import '../state/settings_state.dart';
import '../widgets/media_tile.dart';
import 'open_item.dart';
import '../widgets/channel_sheet.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

const _kindLabels = ['All', 'Channels', 'Movies', 'Series'];
const _kinds = <MediaKind?>[
  null,
  MediaKind.live,
  MediaKind.movie,
  MediaKind.series
];
const _sortLabels = ['Best match', 'A to Z', 'Top rated'];
const _ratingLabels = ['Any rating', '7 and up', '8 and up'];
const _ratingMin = <double?>[null, 7, 8];

class _SearchScreenState extends State<SearchScreen> {
  final _c = TextEditingController();
  String _q = '';
  int _kind = 0, _cat = 0, _rating = 0, _sort = 0;
  bool _filters = false;

  /// Language codes to keep; empty keeps all.
  Set<String> _langs = const {};

  // The last answer, so a rebuild that changes nothing does not search again.
  SearchIndex? _idx;
  String? _memoKey;
  List<MediaItem> _hits = const [];

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  List<MediaItem> _results(AppState s) {
    final idx = s.searchIndex;
    final kind = _kinds[_kind];
    final cats =
        kind == null ? const <String>[] : idx.categoryNames[kind] ?? const [];
    final cat = _cat > 0 && _cat <= cats.length ? cats[_cat - 1] : null;
    final key = '$_q|$_kind|$cat|$_rating|$_sort|${s.favorites.length}|${(_langs.toList()..sort()).join(',')}';
    if (!identical(idx, _idx) || key != _memoKey) {
      _idx = idx;
      _memoKey = key;
      _hits = idx.search(_q,
          filters: SearchFilters(
              kinds: kind == null ? const {} : {kind},
              category: cat,
              minRating: _ratingMin[_rating],
              sort: SearchSort.values[_sort]),
          favorites: s.favorites,
          recent: {for (final r in s.recents) r.key});
      if (_langs.isNotEmpty) {
        _hits = [
          for (final h in _hits)
            if (_langs.contains(languageCodeOf(
                h, h.kind == MediaKind.live ? s.liveCategoryName(h) : s.vodCategoryName(h))))
              h
        ];
      }
    }
    return _hits;
  }

  void _setQuery(String v) => setState(() {
        _q = v;
        _cat = 0;
      });

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final p = LayoutPalette.of(context);
    final size = context.watch<SettingsState>().posterScale;
    final kind = _kinds[_kind];
    final cats = kind == null
        ? const <String>[]
        : s.searchIndex.categoryNames[kind] ?? const [];
    final results = _results(s);
    final langs = {
      for (final list in kind == null
          ? const ['live', 'movie', 'series']
          : [kind == MediaKind.live ? 'live' : kind == MediaKind.movie ? 'movie' : 'series'])
        for (final e in s.languagesFor(list)) e.$1: 0
    }.keys.take(24).map((l) {
      var n = 0;
      for (final list in kind == null
          ? const ['live', 'movie', 'series']
          : [kind == MediaKind.live ? 'live' : kind == MediaKind.movie ? 'movie' : 'series']) {
        for (final e in s.languagesFor(list)) {
          if (e.$1.code == l.code) n += e.$2;
        }
      }
      return (l, n);
    }).toList();
    final active =
        (_cat > 0 ? 1 : 0) + (_rating > 0 ? 1 : 0) + (_sort > 0 ? 1 : 0) + (_langs.isEmpty ? 0 : 1);
    final typed = _q.trim().length >= 2;

    final slivers = <Widget>[];
    if (typed && results.isNotEmpty) {
      for (final k in MediaKind.values) {
        final of = [
          for (final r in results)
            if (r.kind == k) r
        ];
        if (of.isEmpty) continue;
        final live = k == MediaKind.live;
        slivers
          ..add(SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Text(
                  '${const {
                    MediaKind.live: 'Channels',
                    MediaKind.movie: 'Movies',
                    MediaKind.series: 'Series'
                  }[k]}  ·  ${of.length}',
                  style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 16,
                      color: p.muted)),
            ),
          ))
          ..add(SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            sliver: SliverGrid(
              gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: (live ? 220 : 160) * size,
                  childAspectRatio: live ? 16 / 10 : 2 / 3,
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 12),
              delegate: SliverChildBuilderDelegate(
                childCount: of.length,
                (_, i) => MediaTile(
                  item: of[i],
                  favorite: s.isFavorite(of[i]),
                  offline: live && s.isDead(of[i]),
                  onTap: () {
                    s.rememberSearch(_q);
                    openItem(context, of[i], queue: live ? of : null);
                  },
                  onLongPress: () => itemMenu(context, of[i]),
                ),
              ),
            ),
          ));
      }
      slivers.add(const SliverToBoxAdapter(child: SizedBox(height: 24)));
    }

    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
        child: TextField(
          controller: _c,
          textInputAction: TextInputAction.search,
          decoration: InputDecoration(
            prefixIcon: const Icon(Icons.search),
            hintText: 'Search channels, movies, series',
            suffixIcon: _q.isEmpty
                ? null
                : IconButton(
                    tooltip: 'Clear',
                    icon: const Icon(Icons.close),
                    onPressed: () {
                      _c.clear();
                      _setQuery('');
                    }),
          ),
          onChanged: _setQuery,
          onSubmitted: (v) => s.rememberSearch(v),
        ),
      ),
      ChipRow(
        labels: _kindLabels,
        selected: _kind,
        onSelect: (i) => setState(() {
          _kind = i;
          _cat = 0;
        }),
      ),
      Align(
        alignment: Alignment.centerLeft,
        child: Padding(
          padding: const EdgeInsets.only(left: 12),
          child: TextButton.icon(
            onPressed: () => setState(() => _filters = !_filters),
            icon: Icon(_filters ? Icons.expand_less : Icons.tune, size: 18),
            label: Text(active == 0 ? 'Filters' : 'Filters ($active)'),
          ),
        ),
      ),
      if (_filters) ...[
        ChipRow(
            labels: _sortLabels,
            selected: _sort,
            onSelect: (i) => setState(() => _sort = i)),
        ChipRow(
            labels: _ratingLabels,
            selected: _rating,
            onSelect: (i) => setState(() => _rating = i)),
        if (langs.isNotEmpty)
          SizedBox(
            height: 44,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              children: [
                for (final (l, n) in langs)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: FilterChip(
                      label: Text('${l.name}  $n'),
                      selected: _langs.contains(l.code),
                      onSelected: (on) => setState(() => _langs =
                          on ? {..._langs, l.code} : ({..._langs}..remove(l.code))),
                    ),
                  ),
              ],
            ),
          ),
        if (cats.isNotEmpty)
          ChipRow(
            labels: ['Any category', ...cats.take(40)],
            selected: _cat.clamp(0, cats.length > 40 ? 40 : cats.length),
            onSelect: (i) => setState(() => _cat = i),
          )
        else
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                  'Pick Channels, Movies or Series to narrow by category.',
                  style: TextStyle(color: p.muted, fontSize: 13)),
            ),
          ),
      ],
      Expanded(
        child: !typed
            ? _Recent(
                searches: s.recentSearches,
                onPick: (t) {
                  _c.text = t;
                  _c.selection = TextSelection.collapsed(offset: t.length);
                  _setQuery(t);
                },
                onClear: s.clearSearches,
              )
            : results.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                          'Nothing matched "${_q.trim()}"${active > 0 || _kind > 0 ? ' with these filters' : ''}.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: p.muted, fontSize: 16)),
                    ),
                  )
                : CustomScrollView(slivers: slivers),
      ),
    ]);
  }
}

class _Recent extends StatelessWidget {
  final List<String> searches;
  final ValueChanged<String> onPick;
  final VoidCallback onClear;
  const _Recent(
      {required this.searches, required this.onPick, required this.onClear});

  @override
  Widget build(BuildContext context) {
    final p = LayoutPalette.of(context);
    if (searches.isEmpty) {
      return Center(
        child: Text(
            'Type at least two letters.\nSeveral words narrow it down, and small typos are forgiven.',
            textAlign: TextAlign.center,
            style: TextStyle(color: p.muted, height: 1.4)),
      );
    }
    return ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        children: [
          Row(children: [
            Text('Recent searches',
                style: TextStyle(fontWeight: FontWeight.w800, color: p.muted)),
            const Spacer(),
            TextButton(onPressed: onClear, child: const Text('Clear')),
          ]),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final t in searches)
              FocusSurface(
                radius: 20,
                semanticLabel: 'Search $t',
                onTap: () => onPick(t),
                builder: (_, __) => Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  color: p.wash(),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.history, size: 16, color: p.muted),
                    const SizedBox(width: 6),
                    Text(t),
                  ]),
                ),
              ),
          ]),
        ]);
  }
}
