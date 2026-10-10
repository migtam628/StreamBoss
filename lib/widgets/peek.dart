import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../layouts/ui_layout.dart';
import '../models/media.dart';
import '../screens/open_item.dart';
import '../screens/player_screen.dart';
import '../services/details_logic.dart';
import '../services/nav_guard.dart';
import '../services/tmdb.dart';
import '../services/vod_filter.dart';
import '../state/app_state.dart';
import '../state/settings_state.dart';
import 'details_kit.dart';
import 'net_image.dart';
import 'play_options.dart' show clock;

/// A quick look at a movie or series without leaving the list: poster, facts, the plot, and the few
/// things people do next (play, My list, open the full page). Opened by pressing and holding a title,
/// or Menu / Info on a remote.
Future<void> showPeek(BuildContext context, MediaItem item, {Future<TmdbInfo?> Function()? loadInfo}) {
  final p = LayoutPalette.of(context);
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: p.surface,
    constraints: BoxConstraints(maxWidth: 760, maxHeight: MediaQuery.sizeOf(context).height * 0.85),
    builder: (_) => PeekSheet(item: item, loadInfo: loadInfo),
  );
}

class PeekSheet extends StatefulWidget {
  final MediaItem item;
  final Future<TmdbInfo?> Function()? loadInfo;
  const PeekSheet({super.key, required this.item, this.loadInfo});

  @override
  State<PeekSheet> createState() => _PeekSheetState();
}

class _PeekSheetState extends State<PeekSheet> {
  late final Future<TmdbInfo?> _info = widget.loadInfo?.call() ?? loadDetails(context, widget.item);

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final p = LayoutPalette.of(context);
    final item = widget.item;
    final series = item.kind == MediaKind.series;
    final resume = series ? null : s.resumeFor(item);
    final auto = context.watch<SettingsState>().autoResume;
    final watched = s.isWatched(item);

    return SafeArea(
      child: FutureBuilder<TmdbInfo?>(
        future: _info,
        builder: (context, snap) {
          final t = snap.data;
          final poster = t?.poster ?? item.poster;
          final plot = (t?.overview?.isNotEmpty ?? false) ? t!.overview : item.plot;
          final year = t?.year ?? yearOf(item)?.toString();
          final rating = t?.rating?.toStringAsFixed(1) ?? item.rating;
          final chips = [
            if (year != null) year,
            if (t?.runtimeMin != null && t!.runtimeMin! > 0) formatRuntime(t.runtimeMin!),
            if (rating != null && rating != '0' && rating != '0.0') '★ $rating',
            if (t?.certification != null) t!.certification!,
            if (series) 'Series',
          ];
          return SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                if (poster != null)
                  Padding(
                    padding: const EdgeInsets.only(right: 16),
                    child: SizedBox(
                      width: 110,
                      child: AspectRatio(
                        aspectRatio: 2 / 3,
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: ColoredBox(color: p.surfaceHi, child: NetImage(poster)),
                        ),
                      ),
                    ),
                  ),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(item.name, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: p.text)),
                    if (chips.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 8), child: MetaChips(chips)),
                    if (t != null && t.genres.isNotEmpty)
                      Padding(padding: const EdgeInsets.only(top: 8), child: Text(t.genres.join(' · '), style: TextStyle(color: p.muted))),
                    Padding(
                      padding: const EdgeInsets.only(top: 10),
                      child: Text(plot ?? (snap.connectionState == ConnectionState.done ? 'No description from your provider.' : 'Loading…'),
                          maxLines: 6, overflow: TextOverflow.ellipsis, style: TextStyle(color: p.text, height: 1.4)),
                    ),
                    if (s.progressOf(item) case final pr?)
                      Padding(padding: const EdgeInsets.only(top: 10), child: ProgressStripe(pr)),
                  ]),
                ),
              ]),
              const SizedBox(height: 16),
              Wrap(spacing: 10, runSpacing: 10, children: [
                if (!series)
                  FilledButton.icon(
                    autofocus: true,
                    icon: const Icon(Icons.play_arrow),
                    label: Text(resume == null ? (watched ? 'Watch again' : 'Play') : (auto ? 'Resume ${clock(resume)}' : 'Play from start')),
                    onPressed: () {
                      if (!NavGuard.allow()) return;
                      Navigator.pop(context);
                      Navigator.of(context).push(MaterialPageRoute(
                          builder: (_) => PlayerScreen(
                              title: item.name, url: item.streamUrl!, item: item, startAt: auto ? resume : null)));
                    },
                  ),
                if (series)
                  FilledButton.icon(
                    autofocus: true,
                    icon: const Icon(Icons.list),
                    label: const Text('Episodes'),
                    onPressed: () {
                      Navigator.pop(context);
                      openItem(context, item);
                    },
                  )
                else
                  OutlinedButton.icon(
                    icon: const Icon(Icons.info_outline),
                    label: const Text('Full details'),
                    onPressed: () {
                      Navigator.pop(context);
                      openItem(context, item);
                    },
                  ),
                OutlinedButton.icon(
                  icon: Icon(s.isFavorite(item) ? Icons.favorite : Icons.favorite_border),
                  label: Text(s.isFavorite(item) ? 'In My list' : 'My list'),
                  onPressed: () => s.toggleFavorite(item),
                ),
                if (!series)
                  OutlinedButton.icon(
                    icon: Icon(watched ? Icons.visibility_off_outlined : Icons.check_circle_outline),
                    label: Text(watched ? 'Mark not watched' : 'Mark watched'),
                    onPressed: () => s.setWatched([item], !watched),
                  ),
              ]),
            ]),
          );
        },
      ),
    );
  }
}
