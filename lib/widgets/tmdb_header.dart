import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/media.dart';
import '../services/tmdb.dart';
import '../state/settings_state.dart';
import '../theme.dart';

/// Backdrop + overview + cast block, enriched from TMDB when an API key is set.
class TmdbHeader extends StatefulWidget {
  final MediaItem item;
  const TmdbHeader({super.key, required this.item});

  @override
  State<TmdbHeader> createState() => _TmdbHeaderState();
}

class _TmdbHeaderState extends State<TmdbHeader> {
  late final Future<TmdbInfo?> _info =
      TmdbService(context.read<SettingsState>().tmdbKey).lookup(widget.item);

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<TmdbInfo?>(
      future: _info,
      builder: (context, snap) {
        final t = snap.data;
        final overview = t?.overview?.isNotEmpty == true ? t!.overview : widget.item.plot;
        final meta = [
          if (t?.year != null) t!.year!,
          if (t?.runtimeMin != null && t!.runtimeMin! > 0) '${t.runtimeMin} min',
          if (t?.rating != null) '★ ${t!.rating!.toStringAsFixed(1)}'
          else if (widget.item.rating != null) '★ ${widget.item.rating}',
        ].join('  ·  ');
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (t?.backdrop != null)
            AspectRatio(
              aspectRatio: 16 / 7,
              child: CachedNetworkImage(imageUrl: t!.backdrop!, fit: BoxFit.cover),
            ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(widget.item.name,
                  style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800)),
              if (meta.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(meta, style: const TextStyle(color: Boss.accent2)),
                ),
              if (overview != null)
                Padding(padding: const EdgeInsets.only(top: 12), child: Text(overview)),
              if (t != null && t.cast.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text('Cast: ${t.cast.join(', ')}',
                      style: const TextStyle(color: Boss.muted)),
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
              if (snap.connectionState != ConnectionState.done &&
                  context.read<SettingsState>().tmdbKey.isNotEmpty)
                const Padding(
                  padding: EdgeInsets.only(top: 12),
                  child: LinearProgressIndicator(),
                ),
            ]),
          ),
        ]);
      },
    );
  }
}
