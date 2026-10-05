import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../state/app_state.dart';
import '../state/settings_state.dart';
import '../widgets/media_tile.dart';
import 'open_item.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final size = context.watch<SettingsState>().posterScale;
    final q = _q.toLowerCase();
    final results = q.length < 2
        ? const []
        : s.shown.all.where((i) => i.name.toLowerCase().contains(q)).take(200).toList();
    return Column(children: [
      Padding(
        padding: const EdgeInsets.all(16),
        child: TextField(
          decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search), hintText: 'Search channels, movies, series'),
          onChanged: (v) => setState(() => _q = v),
        ),
      ),
      Expanded(
        child: GridView.builder(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 160 * size,
              childAspectRatio: 2 / 3,
              mainAxisSpacing: 12,
              crossAxisSpacing: 12),
          itemCount: results.length,
          itemBuilder: (_, i) => MediaTile(
            item: results[i],
            favorite: s.isFavorite(results[i]),
            onTap: () => openItem(context, results[i]),
          ),
        ),
      ),
    ]);
  }
}
