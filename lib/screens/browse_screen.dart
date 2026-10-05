import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/media.dart';
import '../state/app_state.dart';
import '../state/settings_state.dart';
import '../theme.dart';
import '../widgets/media_tile.dart';
import 'open_item.dart';

class BrowseScreen extends StatefulWidget {
  final MediaKind kind;
  final Catalog catalog;
  const BrowseScreen({super.key, required this.kind, required this.catalog});

  @override
  State<BrowseScreen> createState() => _BrowseScreenState();
}

class _BrowseScreenState extends State<BrowseScreen> {
  String? _cat;

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final size = context.watch<SettingsState>().posterScale;
    final cats = widget.catalog.categoriesFor(widget.kind);
    final all = widget.catalog.itemsFor(widget.kind);
    final items = _cat == null ? all : all.where((i) => i.categoryId == _cat).toList();
    final live = widget.kind == MediaKind.live;

    if (all.isEmpty) {
      return const Center(
          child: Text('Nothing here yet.', style: TextStyle(color: Boss.muted)));
    }

    return Column(children: [
      SizedBox(
        height: 56,
        child: ListView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          children: [
            _chip('All', _cat == null, () => setState(() => _cat = null)),
            for (final c in cats)
              _chip(c.name, _cat == c.id, () => setState(() => _cat = c.id)),
          ],
        ),
      ),
      Expanded(
        child: GridView.builder(
          padding: const EdgeInsets.all(12),
          gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: (live ? 220 : 160) * size,
            childAspectRatio: live ? 16 / 10 : 2 / 3,
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
          ),
          itemCount: items.length,
          itemBuilder: (_, i) {
            final it = items[i];
            return MediaTile(
              item: it,
              favorite: s.isFavorite(it),
              onTap: () => openItem(context, it, queue: items),
              onLongPress: () => s.toggleFavorite(it),
            );
          },
        ),
      ),
    ]);
  }

  Widget _chip(String label, bool sel, VoidCallback onTap) => Padding(
        padding: const EdgeInsets.only(right: 8),
        child: ChoiceChip(
          label: Text(label),
          selected: sel,
          onSelected: (_) => onTap(),
          selectedColor: Boss.accent,
        ),
      );
}
