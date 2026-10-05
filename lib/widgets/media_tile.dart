import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import '../models/media.dart';
import '../theme.dart';
import 'focus_card.dart';

class MediaTile extends StatelessWidget {
  final MediaItem item;
  final bool favorite;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  const MediaTile({
    super.key,
    required this.item,
    required this.onTap,
    this.favorite = false,
    this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final landscape = item.kind == MediaKind.live;
    return FocusCard(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Container(
            color: Boss.surfaceHi,
            child: item.poster == null
                ? _fallback()
                : CachedNetworkImage(
                    imageUrl: item.poster!,
                    fit: landscape ? BoxFit.contain : BoxFit.cover,
                    errorWidget: (_, __, ___) => _fallback(),
                    placeholder: (_, __) => const SizedBox.shrink(),
                  ),
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
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
            ),
          ),
          if (favorite)
            const Positioned(
              top: 6,
              right: 6,
              child: Icon(Icons.favorite, size: 16, color: Boss.accent),
            ),
        ],
      ),
    );
  }

  Widget _fallback() => Center(
        child: Icon(
          switch (item.kind) {
            MediaKind.live => Icons.live_tv,
            MediaKind.movie => Icons.movie,
            MediaKind.series => Icons.tv,
          },
          color: Boss.muted,
          size: 36,
        ),
      );
}
