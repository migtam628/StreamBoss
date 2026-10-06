import 'package:flutter/material.dart';
import '../models/media.dart';
import '../layouts/ui_layout.dart';
import 'focus_card.dart';
import 'net_image.dart';
import 'tv.dart';

class MediaTile extends StatelessWidget {
  final MediaItem item;
  final bool favorite;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final ValueChanged<bool>? onFocus;
  final bool autofocus;

  const MediaTile({
    super.key,
    required this.item,
    required this.onTap,
    this.favorite = false,
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
            child: item.poster == null
                ? _fallback(pal)
                : NetImage(item.poster!,
                    fit: landscape ? BoxFit.contain : BoxFit.cover, fallback: () => _fallback(pal)),
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
