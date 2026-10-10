import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../layouts/common.dart';
import '../layouts/ui_layout.dart';
import '../models/media.dart';
import '../services/details_logic.dart';
import '../services/languages.dart';
import '../services/tmdb.dart';
import '../state/app_state.dart';
import '../state/settings_state.dart';
import '../widgets/collections_sheet.dart';
import '../widgets/details_kit.dart';
import '../widgets/tv.dart';
import 'open_item.dart';
import 'player_screen.dart';

/// The series page: the Showcase picture, a Continue button that knows which episode is next, and tabs
/// for Episodes (by season, with progress and a mark for watched), Overview, Cast, More like this and
/// Details.
class SeriesScreen extends StatefulWidget {
  final MediaItem series;

  /// For tests: where the episodes and the details come from instead of the provider.
  final Future<List<Episode>> Function()? loadEpisodes;
  final Future<TmdbInfo?> Function()? loadInfo;
  const SeriesScreen({super.key, required this.series, this.loadEpisodes, this.loadInfo});

  @override
  State<SeriesScreen> createState() => _SeriesScreenState();
}

class _Ep {
  final Episode e;
  final MediaItem item;
  const _Ep(this.e, this.item);
}

class _SeriesScreenState extends State<SeriesScreen> {
  late final Future<TmdbInfo?> _info = widget.loadInfo?.call() ?? loadDetails(context, widget.series);
  late final Future<List<Episode>> _eps = widget.loadEpisodes?.call() ?? context.read<AppState>().episodes(widget.series);
  late final Future<List<Object?>> _both = Future.wait<Object?>([_info, _eps.catchError((_) => <Episode>[])]);
  int _tab = 0;
  int? _season; // null = the one that holds the next episode

  MediaItem get series => widget.series;

  /// One item per episode, so resume and "continue watching" are per episode and the next one can follow.
  List<_Ep> _items(List<Episode> eps) => [
        for (final e in eps)
          _Ep(
            e,
            MediaItem(
              id: 'ep${e.id}',
              name: '${series.name} – ${e.title}',
              kind: MediaKind.movie,
              streamUrl: e.url,
              poster: series.poster,
            ),
          ),
      ];

  void _play(List<_Ep> all, int i, {Duration? at}) {
    final s = context.read<AppState>();
    final ep = all[i].item;
    final auto = context.read<SettingsState>().autoResume;
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => PlayerScreen(
        title: ep.name,
        url: ep.streamUrl!,
        item: ep,
        startAt: at ?? (auto ? s.resumeFor(ep) : null),
        episodes: [for (final x in all) x.item],
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final p = LayoutPalette.of(context);
    return Scaffold(
      backgroundColor: p.bg,
      body: TvSafe(
        child: FutureBuilder<List<Object?>>(
          future: _both,
          builder: (context, snap) {
            final loading = snap.connectionState != ConnectionState.done;
            final t = snap.data?[0] as TmdbInfo?;
            final all = _items((snap.data?[1] as List<Episode>?) ?? const []);
            final seasons = {for (final x in all) x.e.season}.toList()..sort();
            final next = nextUpIndex(
              [for (final x in all) s.isWatched(x.item)],
              [for (final x in all) s.resumeFor(x.item) != null],
            );
            final rating = t?.rating?.toStringAsFixed(1) ?? series.rating;
            final lang = languageCodeOf(series, s.vodCategoryName(series));
            final chips = [
              if (t?.year != null) t!.year!,
              if (seasons.isNotEmpty) '${seasons.length} ${seasons.length == 1 ? 'season' : 'seasons'}',
              if (all.isNotEmpty) '${all.length} episodes',
              if (rating != null && rating != '0' && rating != '0.0') '★ $rating',
              if (t?.certification != null) t!.certification!,
              if (t?.status != null) t!.status!,
              if (lang != null) languageName(lang),
            ];

            Widget button(IconData icon, String label, VoidCallback onTap, {bool primary = false, bool autofocus = false}) =>
                primary
                    ? FilledButton.icon(autofocus: autofocus, onPressed: onTap, icon: Icon(icon), label: Text(label))
                    : OutlinedButton.icon(autofocus: autofocus, onPressed: onTap, icon: Icon(icon), label: Text(label));

            String nextLabel() {
              final x = all[next!];
              return 'Continue S${x.e.season} · E${x.e.number}';
            }

            final buttons = Wrap(spacing: 10, runSpacing: 10, children: [
              if (all.isNotEmpty && next != null)
                button(Icons.play_arrow, nextLabel(), () => _play(all, next), primary: true, autofocus: true)
              else if (all.isNotEmpty)
                button(Icons.replay, 'Watch again from the start', () {
                  s.setWatched([for (final x in all) x.item], false);
                  _play(all, 0, at: Duration.zero);
                }, primary: true, autofocus: true),
              button(s.isFavorite(series) ? Icons.favorite : Icons.favorite_border, s.isFavorite(series) ? 'In My list' : 'My list',
                  () => s.toggleFavorite(series)),
              button(Icons.collections_bookmark_outlined,
                  s.collections.values.any((l) => l.contains(series.key)) ? 'In a collection' : 'Collection',
                  () => showCollectionsSheet(context, series)),
              if (t?.trailerKey != null)
                button(Icons.ondemand_video, 'Trailer',
                    () => launchUrl(Uri.parse('https://www.youtube.com/watch?v=${t!.trailerKey}'), mode: LaunchMode.externalApplication)),
            ]);

            const tabs = ['Episodes', 'Overview', 'Cast', 'More like this', 'Details'];
            final overview = (t?.overview?.isNotEmpty ?? false) ? t!.overview : series.plot;
            return ListView(children: [
              DetailsHero(
                title: series.name,
                backdrop: t?.backdrop,
                poster: t?.poster ?? series.poster,
                tagline: t?.tagline,
                chips: chips,
                onBack: () => Navigator.of(context).maybePop(),
              ),
              if (loading) const LinearProgressIndicator(minHeight: 2),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 14, 20, 4),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  buttons,
                  if (next != null && all.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(_nextLine(s, all[next]), style: TextStyle(color: p.muted, fontSize: 13)),
                    ),
                ]),
              ),
              DetailTabs(labels: tabs, selected: _tab, onSelect: (i) => setState(() => _tab = i)),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
                child: switch (_tab) {
                  0 => _episodes(p, s, all, seasons, next, snap.connectionState == ConnectionState.done),
                  1 => _overview(p, overview, t),
                  2 => _cast(p, t),
                  3 => _similar(s),
                  _ => _details(p, s, t, all, seasons, lang),
                },
              ),
            ]);
          },
        ),
      ),
    );
  }

  String _nextLine(AppState s, _Ep x) {
    final left = s.resumeFor(x.item);
    final total = s.durations[x.item.key];
    final mins = x.e.minutes;
    final bits = [
      x.e.title,
      if (left != null && total != null && total - left.inMilliseconds > 60000)
        '${((total - left.inMilliseconds) / 60000).round()} min left'
      else if (mins != null)
        '$mins min',
    ];
    return bits.join(' · ');
  }

  Widget _episodes(LayoutPalette p, AppState s, List<_Ep> all, List<int> seasons, int? next, bool done) {
    if (all.isEmpty) {
      return Padding(
        padding: const EdgeInsets.only(top: 16),
        child: Text(done ? 'No episodes listed by your provider.' : 'Loading episodes…', style: TextStyle(color: p.muted)),
      );
    }
    final current = _season ?? (next == null ? seasons.first : all[next].e.season);
    final inSeason = [for (var i = 0; i < all.length; i++) if (all[i].e.season == current) i];
    final seen = inSeason.where((i) => s.isWatched(all[i].item)).length;
    final everyWatched = seen == inSeason.length;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      if (seasons.length > 1)
        ChipRow(
          labels: [for (final n in seasons) n == 0 ? 'Specials' : 'Season $n'],
          selected: seasons.indexOf(current),
          onSelect: (i) => setState(() => _season = seasons[i]),
          padding: const EdgeInsets.symmetric(vertical: 8),
        ),
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(children: [
          Expanded(child: Text('${inSeason.length} episodes · $seen watched', style: TextStyle(color: p.muted))),
          TextButton.icon(
            icon: Icon(everyWatched ? Icons.visibility_off_outlined : Icons.check_circle_outline, size: 18),
            label: Text(everyWatched ? 'Mark season not watched' : 'Mark season watched'),
            onPressed: () {
              // Stay on this season even though the next episode may now be in another one.
              setState(() => _season = current);
              s.setWatched([for (final i in inSeason) all[i].item], !everyWatched);
            },
          ),
        ]),
      ),
      for (final i in inSeason) _row(p, s, all, i),
    ]);
  }

  Widget _row(LayoutPalette p, AppState s, List<_Ep> all, int i) {
    final x = all[i];
    final watched = s.isWatched(x.item);
    final progress = watched ? null : s.progressOf(x.item);
    final isNew = isRecentEpisode(x.e.airDate);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: FocusSurface(
        radius: 12,
        semanticLabel: 'Episode ${x.e.number}, ${x.e.title}',
        onTap: () => _play(all, i),
        // Press and hold, or Menu / Info on a remote, flips watched.
        onLongPress: () => s.setWatched([x.item], !watched),
        builder: (_, __) => Container(
          color: p.wash(0.06),
          padding: const EdgeInsets.all(12),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SizedBox(
              width: 34,
              child: watched
                  ? Icon(Icons.check_circle, color: p.accent)
                  : Text('${x.e.number}', style: TextStyle(color: p.muted, fontWeight: FontWeight.w800, fontSize: 18)),
            ),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Flexible(
                    child: Text(x.e.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: watched ? p.muted : p.text, fontWeight: FontWeight.w700, fontSize: 16)),
                  ),
                  if (isNew)
                    Container(
                      margin: const EdgeInsets.only(left: 8),
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                      decoration: BoxDecoration(color: p.accent, borderRadius: BorderRadius.circular(4)),
                      child: Text('NEW', style: TextStyle(color: p.onAccent, fontSize: 10, fontWeight: FontWeight.w800)),
                    ),
                ]),
                if (x.e.minutes != null || x.e.plot != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      [if (x.e.minutes != null) '${x.e.minutes} min', if (x.e.plot != null) x.e.plot!].join(' · '),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: p.muted, fontSize: 13),
                    ),
                  ),
                if (progress != null) Padding(padding: const EdgeInsets.only(top: 8), child: ProgressStripe(progress)),
              ]),
            ),
            Icon(Icons.play_circle_outline, color: p.accent),
          ]),
        ),
      ),
    );
  }

  Widget _overview(LayoutPalette p, String? overview, TmdbInfo? t) =>
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const SizedBox(height: 8),
        Text(overview ?? 'No description from your provider yet.', style: TextStyle(color: p.text, fontSize: 16, height: 1.45)),
        if (t != null && t.genres.isNotEmpty) ...[const DetailsHeading('Genres'), MetaChips(t.genres)],
        if (t != null && t.directors.isNotEmpty) ...[
          const DetailsHeading('Created by'),
          Text(t.directors.join(', '), style: TextStyle(color: p.text)),
        ],
      ]);

  Widget _cast(LayoutPalette p, TmdbInfo? t) {
    final people = t?.people ?? const <Person>[];
    if (people.isEmpty) {
      return Padding(
        padding: const EdgeInsets.only(top: 12),
        child: Text('No cast listed. Add a TMDB key in Settings for photos and roles.', style: TextStyle(color: p.muted)),
      );
    }
    return Padding(padding: const EdgeInsets.only(top: 12), child: PeopleWrap(people));
  }

  Widget _similar(AppState s) {
    final more = similarTo(series, s.shown.series);
    if (more.isEmpty) {
      return Padding(
        padding: const EdgeInsets.only(top: 12),
        child: Text('Nothing else in this category.', style: TextStyle(color: LayoutPalette.of(context).muted)),
      );
    }
    return Padding(padding: const EdgeInsets.only(top: 12), child: TitleShelf(items: more, onOpen: (m) => openItem(context, m)));
  }

  Widget _details(LayoutPalette p, AppState s, TmdbInfo? t, List<_Ep> all, List<int> seasons, String? lang) {
    final total = all.fold<int>(0, (a, x) => a + (x.e.minutes ?? 0));
    final last = all.map((x) => x.e.airDate).whereType<String>().fold<String?>(null, (a, d) => a == null || d.compareTo(a) > 0 ? d : a);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const DetailsHeading('Facts'),
      FactsTable([
        ('Year', t?.year),
        ('Seasons', seasons.isEmpty ? null : '${seasons.length}'),
        ('Episodes', all.isEmpty ? null : '${all.length}'),
        ('Total running time', total > 0 ? formatRuntime(total) : null),
        ('Latest episode aired', last),
        ('Genre', (t?.genres.isEmpty ?? true) ? null : t!.genres.join(' · ')),
        ('Network', t?.network),
        ('Status', t?.status),
        ('Country', (t?.countries.isEmpty ?? true) ? null : t!.countries.join(' · ')),
        ('Age rating', t?.certification),
        ('Language', lang == null ? null : languageName(lang)),
        ('Category', s.vodCategoryName(series)),
      ]),
    ]);
  }
}
