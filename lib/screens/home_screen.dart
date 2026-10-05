import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/media.dart';
import '../state/app_state.dart';
import '../state/settings_state.dart';
import '../theme.dart';
import '../widgets/media_tile.dart';
import '../widgets/tv.dart';
import 'open_item.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final c = s.shown;
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
    final tv = TvScope.of(context);
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 20),
      padding: EdgeInsets.all(tv ? 32 : 24),
      height: tv ? 240 : 200,
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
              style: TextStyle(fontSize: tv ? 34 : 26, fontWeight: FontWeight.w800)),
          const SizedBox(height: 12),
          FilledButton.icon(
            // A remote has no pointer, so land the cursor on the main action.
            autofocus: tv,
            style: FilledButton.styleFrom(backgroundColor: Colors.white, foregroundColor: Colors.black).copyWith(
              // White on white would hide the TV focus outline, so this button uses a dark one.
              side: WidgetStateProperty.resolveWith(
                  (s) => s.contains(WidgetState.focused) ? const BorderSide(color: Colors.black, width: 4) : null),
            ),
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
    final size = context.watch<SettingsState>().posterScale;
    final tv = TvScope.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text(title, style: TextStyle(fontSize: tv ? 22 : 18, fontWeight: FontWeight.w700)),
        ),
        const SizedBox(height: 10),
        SizedBox(
          // Extra height on TV leaves room for the focused card's lift and glow.
          height: 190 * size + (tv ? 24 : 0),
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: EdgeInsets.symmetric(horizontal: tv ? 30 : 16, vertical: tv ? 14 : 6),
            itemCount: items.length,
            separatorBuilder: (_, __) => SizedBox(width: tv ? 26 : 12),
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
