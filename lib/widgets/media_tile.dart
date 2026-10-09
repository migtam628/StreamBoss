import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../state/app_state.dart';
import '../models/media.dart';
import '../layouts/ui_layout.dart';
import 'focus_card.dart';
import 'net_image.dart';
import 'tv.dart';

class MediaTile extends StatelessWidget {
  final MediaItem item;
  final bool favorite;

  /// A live channel that failed the last check.
  final bool offline;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final ValueChanged<bool>? onFocus;
  final bool autofocus;

  const MediaTile({
    super.key,
    required this.item,
    required this.onTap,
    this.favorite = false,
    this.offline = false,
    this.onLongPress,
    this.onFocus,
    this.autofocus = false,
  });

  @override
  Widget build(BuildContext context) {
    final landscape = item.kind == MediaKind.live;
    final tv = TvScope.of(context);
    final pal = LayoutPalette.of(context);
    return FocusCard(
      onTap: onTap,
      onLongPress: onLongPress,
      onFocus: onFocus,
      autofocus: autofocus,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Container(
            color: pal.surfaceHi,
            child: _Art(item: item, fit: landscape ? BoxFit.contain : BoxFit.cover, fallback: () => _fallback(pal)),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Container(
              padding: const EdgeInsets.fromLTRB(8, 18, 8, 8),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.transparent, Color(0xDD000000)],
                ),
              ),
              child: Text(item.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: Colors.white, fontSize: tv ? 15 : 12, fontWeight: FontWeight.w600)),
            ),
          ),
          if (offline)
            Positioned.fill(
              child: ColoredBox(
                color: Colors.black.withValues(alpha: 0.55),
                child: const Align(
                  alignment: Alignment.topLeft,
                  child: Padding(
                    padding: EdgeInsets.all(6),
                    child: Text('OFFLINE',
                        style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 1)),
                  ),
                ),
              ),
            ),
          if (favorite)
            Positioned(
              top: 6,
              right: 6,
              child: Icon(Icons.favorite, size: 16, color: pal.accent),
            ),
        ],
      ),
    );
  }

  Widget _fallback(LayoutPalette pal) => Center(
        child: Icon(
          switch (item.kind) {
            MediaKind.live => Icons.live_tv,
            MediaKind.movie => Icons.movie,
            MediaKind.series => Icons.tv,
          },
          color: pal.muted,
          size: 36,
        ),
      );
}

/// The poster of [item], or, when it has none and there is a TMDB key, the one TMDB has.
class _Art extends StatefulWidget {
  final MediaItem item;
  final BoxFit fit;
  final Widget Function() fallback;
  const _Art({required this.item, required this.fit, required this.fallback});

  @override
  State<_Art> createState() => _ArtState();
}

class _ArtState extends State<_Art> {
  Future<String?>? _future;

  void _ask() {
    final i = widget.item;
    if (i.poster != null || i.kind == MediaKind.live) {
      _future = null;
      return;
    }
    _future = Provider.of<AppState?>(context, listen: false)?.posterFor(i);
  }

  @override
  void initState() {
    super.initState();
    _ask();
  }

  @override
  void didUpdateWidget(_Art old) {
    super.didUpdateWidget(old);
    if (old.item.key != widget.item.key) _ask();
  }

  @override
  Widget build(BuildContext context) {
    final i = widget.item;
    if (i.poster != null) return NetImage(i.poster!, fit: widget.fit, fallback: widget.fallback);
    final f = _future;
    if (f == null) return widget.fallback();
    return FutureBuilder<String?>(
      future: f,
      builder: (_, snap) {
        final url = snap.data;
        return url == null || url.isEmpty ? widget.fallback() : NetImage(url, fit: widget.fit, fallback: widget.fallback);
      },
    );
  }
}
