import 'package:flutter/material.dart';
import '../layouts/ui_layout.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/media.dart';
import '../services/tmdb.dart';
import '../state/app_state.dart';
import '../state/settings_state.dart';
import 'net_image.dart';

/// Poster, backdrop, overview, cast and trailer for a movie or series.
/// Details come from the provider itself (Xtream) and from TMDB when a key is set;
/// TMDB wins where both have a value, the provider fills the gaps.
class TmdbHeader extends StatefulWidget {
  final MediaItem item;
  const TmdbHeader({super.key, required this.item});

  @override
  State<TmdbHeader> createState() => _TmdbHeaderState();
}

class _TmdbHeaderState extends State<TmdbHeader> {
  late final Future<TmdbInfo?> _info = () async {
    final key = context.read<SettingsState>().tmdbKey;
    final app = context.read<AppState>();
    final r = await Future.wait<TmdbInfo?>([
      TmdbService(key).lookup(widget.item),
      app.providerInfo(widget.item),
    ]);
    return mergeInfo(r[0], r[1]);
  }();

  Widget _image(String url) => NetImage(url);

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<TmdbInfo?>(
      future: _info,
      builder: (context, snap) {
        final t = snap.data;
        final overview = t?.overview?.isNotEmpty == true ? t!.overview : widget.item.plot;
        final poster = t?.poster ?? widget.item.poster;
        final rating = t?.rating?.toStringAsFixed(1) ?? widget.item.rating;
        final meta = [
          if (t?.year != null) t!.year!,
          if (t?.runtimeMin != null && t!.runtimeMin! > 0) '${t.runtimeMin} min',
          if (rating != null) '★ $rating',
        ].join('  ·  ');

        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (t?.backdrop != null)
            AspectRatio(aspectRatio: 16 / 7, child: _image(t!.backdrop!)),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              if (poster != null)
                Padding(
                  padding: const EdgeInsets.only(right: 18),
                  child: SizedBox(
                    width: 140,
                    child: AspectRatio(
                      aspectRatio: 2 / 3,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: ColoredBox(color: LayoutPalette.of(context).surfaceHi, child: _image(poster)),
                      ),
                    ),
                  ),
                ),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(widget.item.name,
                      style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800)),
                  if (meta.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(meta, style: TextStyle(color: LayoutPalette.of(context).accent2)),
                    ),
                  if (overview != null)
                    Padding(padding: const EdgeInsets.only(top: 12), child: Text(overview)),
                  if (t != null && t.cast.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Text('Cast: ${t.cast.join(', ')}',
                          style: TextStyle(color: LayoutPalette.of(context).muted)),
                    ),
                  if (t?.trailerKey != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: OutlinedButton.icon(
                        icon: const Icon(Icons.ondemand_video),
                        label: const Text('Trailer'),
                        onPressed: () => launchUrl(
                            Uri.parse('https://www.youtube.com/watch?v=${t!.trailerKey}'),
                            mode: LaunchMode.externalApplication),
                      ),
                    ),
                  if (snap.connectionState != ConnectionState.done)
                    const Padding(
                      padding: EdgeInsets.only(top: 12),
                      child: LinearProgressIndicator(),
                    ),
                ]),
              ),
            ]),
          ),
        ]);
      },
    );
  }
}
