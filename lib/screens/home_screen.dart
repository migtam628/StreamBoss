import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/media.dart';
import '../state/app_state.dart';
import '../theme.dart';
import '../widgets/media_tile.dart';
import 'open_item.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final c = s.catalog;
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 16),
      children: [
        _Hero(item: c.movies.isNotEmpty ? c.movies.first : (c.live.isNotEmpty ? c.live.first : null)),
        _Shelf(title: 'Continue watching', items: s.recents),
        _Shelf(title: 'My list', items: s.favoriteItems),
        _Shelf(title: 'Live now', items: c.live.take(20).toList()),
        _Shelf(title: 'Movies', items: c.movies.take(30).toList()),
        _Shelf(title: 'Series', items: c.series.take(30).toList()),
      ],
    );
  }
}

class _Hero extends StatelessWidget {
  final MediaItem? item;
  const _Hero({this.item});

  @override
  Widget build(BuildContext context) {
    if (item == null) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 20),
      padding: const EdgeInsets.all(24),
      height: 200,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: const LinearGradient(
            colors: [Boss.accent, Color(0xFF6A1B9A)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          Text(item!.name,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800)),
          const SizedBox(height: 12),
          FilledButton.icon(
            style: FilledButton.styleFrom(
                backgroundColor: Colors.white, foregroundColor: Colors.black),
            onPressed: () => openItem(context, item!),
            icon: const Icon(Icons.play_arrow),
            label: const Text('Play'),
          ),
        ],
      ),
    );
  }
}

class _Shelf extends StatelessWidget {
  final String title;
  final List<MediaItem> items;
  const _Shelf({required this.title, required this.items});

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox.shrink();
    final s = context.read<AppState>();
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text(title,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
        ),
        const SizedBox(height: 10),
        SizedBox(
          height: 190,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            itemCount: items.length,
            separatorBuilder: (_, __) => const SizedBox(width: 12),
            itemBuilder: (_, i) {
              final it = items[i];
              return AspectRatio(
                aspectRatio: it.kind == MediaKind.live ? 16 / 10 : 2 / 3,
                child: MediaTile(
                  item: it,
                  favorite: s.isFavorite(it),
                  onTap: () => openItem(context, it),
                  onLongPress: () => s.toggleFavorite(it),
                ),
              );
            },
          ),
        ),
      ]),
    );
  }
}
