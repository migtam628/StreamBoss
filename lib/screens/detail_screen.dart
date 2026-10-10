import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../layouts/ui_layout.dart';
import '../models/media.dart';
import '../services/details_logic.dart';
import '../services/languages.dart';
import '../services/tmdb.dart';
import '../services/nav_guard.dart';
import '../state/app_state.dart';
import '../state/settings_state.dart';
import '../widgets/collections_sheet.dart';
import '../widgets/details_kit.dart';
import '../widgets/play_options.dart';
import '../widgets/tv.dart';
import 'open_item.dart';
import 'player_screen.dart';

/// The movie page: a big picture with the title and facts, the play buttons, and tabs for the rest
/// (Overview, Cast, More like this, Details).
class DetailScreen extends StatefulWidget {
  final MediaItem item;

  /// For tests: where the details come from instead of TMDB and the provider.
  final Future<TmdbInfo?> Function()? loadInfo;
  const DetailScreen({super.key, required this.item, this.loadInfo});

  @override
  State<DetailScreen> createState() => _DetailScreenState();
}

class _DetailScreenState extends State<DetailScreen> {
  late final Future<TmdbInfo?> _info = widget.loadInfo?.call() ?? loadDetails(context, widget.item);
  int _tab = 0;

  MediaItem get item => widget.item;

  void _play(MediaItem what, {Duration? at, required PlayRequest? req}) {
    if (!NavGuard.allow()) return;
    Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => PlayerScreen(
            title: what.name, url: what.streamUrl!, item: what, startAt: at, choices: req?.choices)));
  }

  Future<void> _options() async {
    final s = context.read<AppState>();
    final req = await showPlayOptions(context,
        item: item, resume: s.resumeFor(item), versions: versionsOf(item, s.shown.movies));
    if (req != null && mounted) {
      if (req.startAt == null) s.positions.remove(req.item.key);
      _play(req.item, at: req.startAt, req: req);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final p = LayoutPalette.of(context);
    final auto = context.watch<SettingsState>().autoResume;
    final resume = s.resumeFor(item);
    final watched = s.isWatched(item);

    return Scaffold(
      backgroundColor: p.bg,
      body: TvSafe(
        child: FutureBuilder<TmdbInfo?>(
          future: _info,
          builder: (context, snap) {
            final t = snap.data;
            final loading = snap.connectionState != ConnectionState.done;
            final overview = (t?.overview?.isNotEmpty ?? false) ? t!.overview : item.plot;
            final rating = t?.rating?.toStringAsFixed(1) ?? item.rating;
            final tech = t?.tech;
            final lang = languageCodeOf(item, s.vodCategoryName(item));
            final chips = [
              if (t?.year != null) t!.year!,
              if (t?.runtimeMin != null && t!.runtimeMin! > 0) formatRuntime(t.runtimeMin!),
              if (rating != null && rating != '0' && rating != '0.0') '★ $rating',
              if (t?.certification != null) t!.certification!,
              tech?.resolution ?? qualityTagOf(item.name),
              tech?.channels,
              if (lang != null) languageName(lang),
            ].whereType<String>().toList();

            Widget button(IconData icon, String label, VoidCallback onTap, {bool primary = false, bool autofocus = false}) =>
                primary
                    ? FilledButton.icon(autofocus: autofocus, onPressed: onTap, icon: Icon(icon), label: Text(label))
                    : OutlinedButton.icon(autofocus: autofocus, onPressed: onTap, icon: Icon(icon), label: Text(label));

            final left = resume == null ? null : Duration(milliseconds: (s.durations[item.key] ?? 0) - resume.inMilliseconds);
            final buttons = Wrap(spacing: 10, runSpacing: 10, children: [
              if (resume == null)
                button(Icons.play_arrow, watched ? 'Watch again' : 'Play', () => _play(item, req: null), primary: true, autofocus: true)
              else if (auto) ...[
                button(Icons.play_arrow, 'Resume ${clock(resume)}', () => _play(item, at: resume, req: null), primary: true, autofocus: true),
                button(Icons.replay, 'Start over', () {
                  s.positions.remove(item.key);
                  _play(item, req: null);
                }),
              ] else ...[
                button(Icons.play_arrow, 'Play from start', () => _play(item, req: null), primary: true, autofocus: true),
                button(Icons.history, 'Resume ${clock(resume)}', () => _play(item, at: resume, req: null)),
              ],
              button(Icons.tune, 'Play options', _options),
              button(s.isFavorite(item) ? Icons.favorite : Icons.favorite_border, s.isFavorite(item) ? 'In My list' : 'My list',
                  () => s.toggleFavorite(item)),
              button(Icons.collections_bookmark_outlined,
                  s.collections.values.any((l) => l.contains(item.key)) ? 'In a collection' : 'Collection',
                  () => showCollectionsSheet(context, item)),
              if (t?.trailerKey != null)
                button(Icons.ondemand_video, 'Trailer', () => launchUrl(Uri.parse('https://www.youtube.com/watch?v=${t!.trailerKey}'), mode: LaunchMode.externalApplication)),
              button(watched ? Icons.visibility_off_outlined : Icons.check_circle_outline, watched ? 'Mark not watched' : 'Mark watched',
                  () => s.setWatched([item], !watched)),
            ]);

            const tabs = ['Overview', 'Cast', 'More like this', 'Details'];
            return ListView(children: [
              DetailsHero(
                title: item.name,
                backdrop: t?.backdrop,
                poster: t?.poster ?? item.poster,
                tagline: t?.tagline,
                chips: chips,
                onBack: () => Navigator.of(context).maybePop(),
              ),
              if (loading) const LinearProgressIndicator(minHeight: 2),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 14, 20, 4),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  buttons,
                  if (left != null && left.inMinutes > 0)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text('${left.inMinutes >= 60 ? formatRuntime(left.inMinutes) : '${left.inMinutes} min'} left',
                          style: TextStyle(color: p.muted, fontSize: 13)),
                    ),
                  if (s.progressOf(item) case final pr?)
                    Padding(padding: const EdgeInsets.only(top: 6), child: SizedBox(width: 280, child: ProgressStripe(pr))),
                ]),
              ),
              DetailTabs(labels: tabs, selected: _tab, onSelect: (i) => setState(() => _tab = i)),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
                child: switch (_tab) {
                  0 => _overview(p, overview, t),
                  1 => _cast(p, t),
                  2 => _similar(s),
                  _ => _details(p, s, t, lang),
                },
              ),
            ]);
          },
        ),
      ),
    );
  }

  Widget _overview(LayoutPalette p, String? overview, TmdbInfo? t) =>
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const SizedBox(height: 8),
        Text(overview ?? 'No description from your provider yet.', style: TextStyle(color: p.text, fontSize: 16, height: 1.45)),
        if (t != null && t.genres.isNotEmpty) ...[
          const DetailsHeading('Genres'),
          MetaChips(t.genres),
        ],
        if (t != null && t.directors.isNotEmpty) ...[
          const DetailsHeading('Directed by'),
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
    final more = similarTo(item, s.shown.movies);
    if (more.isEmpty) {
      return Padding(
        padding: const EdgeInsets.only(top: 12),
        child: Text('Nothing else in this category.', style: TextStyle(color: LayoutPalette.of(context).muted)),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: TitleShelf(items: more, onOpen: (m) => openItem(context, m)),
    );
  }

  Widget _details(LayoutPalette p, AppState s, TmdbInfo? t, String? lang) {
    final tech = t?.tech;
    final versions = versionsOf(item, s.shown.movies);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const DetailsHeading('Facts'),
      FactsTable([
        ('Year', t?.year),
        ('Runtime', t?.runtimeMin == null ? null : formatRuntime(t!.runtimeMin!)),
        ('Genre', (t?.genres.isEmpty ?? true) ? null : t!.genres.join(' · ')),
        ('Country', (t?.countries.isEmpty ?? true) ? null : t!.countries.join(' · ')),
        ('Director', (t?.directors.isEmpty ?? true) ? null : t!.directors.join(', ')),
        ('Age rating', t?.certification),
        ('Language', lang == null ? null : languageName(lang)),
        ('Category', s.vodCategoryName(item)),
      ]),
      if (tech != null) ...[
        const DetailsHeading('The file'),
        FactsTable([
          ('Video', [tech.resolution, tech.videoCodec?.toUpperCase()].whereType<String>().join(' · ')),
          ('Audio', [tech.audioCodec?.toUpperCase(), tech.channels, tech.audioLanguage?.toUpperCase()].whereType<String>().join(' · ')),
          ('Bitrate', tech.bitrateKbps == null ? null : '${(tech.bitrateKbps! / 1000).toStringAsFixed(1)} Mb/s'),
          ('Container', tech.container?.toUpperCase()),
        ]),
      ],
      if (versions.isNotEmpty) ...[
        const DetailsHeading('Other copies in your library'),
        for (final v in versions)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.movie_outlined, color: p.accent),
            title: Text(qualityTagOf(v.name) ?? 'Copy', style: TextStyle(color: p.text, fontWeight: FontWeight.w700)),
            subtitle: Text('${v.name}  ·  ${s.vodCategoryName(v)}', maxLines: 1, overflow: TextOverflow.ellipsis),
            onTap: () => openItem(context, v),
          ),
      ],
    ]);
  }
}
