import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../layouts/ui_layout.dart';
import '../state/app_state.dart';
import '../state/settings_state.dart';
import '../widgets/collections_sheet.dart';
import '../widgets/media_tile.dart';
import 'open_item.dart';
import 'settings/settings_widgets.dart' show confirmDialog;
import '../l10n/l10n.dart';

/// Every collection with how many items it holds; opens one, renames it or deletes it.
class CollectionsScreen extends StatelessWidget {
  const CollectionsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final p = LayoutPalette.of(context);
    final names = app.collections.keys.toList();
    return Scaffold(
      appBar: AppBar(title: Text(tr('Collections')), backgroundColor: p.bg),
      body: ListView(children: [
        if (names.isEmpty)
          Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              tr('A collection is a list you name, like "Friday movie night" or "Kids".\n'
              'Open a movie or a series and choose Add to collection.'),
              style: TextStyle(color: p.muted, height: 1.4),
            ),
          ),
        for (final n in names)
          ListTile(
            leading: const Icon(Icons.collections_bookmark_outlined),
            title: Text(n),
            subtitle: Text(
                '${app.collectionItems(n).length} here · ${app.collections[n]!.length} saved'),
            trailing: PopupMenuButton<String>(
              onSelected: (v) async {
                if (v == 'rename') {
                  final to = await askCollectionName(context,
                      title: tr('Rename collection'), initial: n);
                  if (to != null &&
                      to.isNotEmpty &&
                      !app.renameCollection(n, to) &&
                      context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(tr('That name is taken.'))));
                  }
                } else if (v == 'delete') {
                  if (await confirmDialog(context,
                      title: trf('Delete "{name}"?', {'name': n}),
                      body: tr('The items stay in your library.'),
                      confirm: tr('Delete'))) {
                    app.deleteCollection(n);
                  }
                }
              },
              itemBuilder: (_) => [
                PopupMenuItem(value: 'rename', child: Text(tr('Rename'))),
                PopupMenuItem(value: 'delete', child: Text(tr('Delete'))),
              ],
            ),
            onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => CollectionScreen(name: n))),
          ),
        ListTile(
          leading: const Icon(Icons.add),
          title: Text(tr('New collection')),
          onTap: () async {
            final n = await askCollectionName(context);
            if (n != null &&
                n.isNotEmpty &&
                !app.createCollection(n) &&
                context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(tr('That name is taken.'))));
            }
          },
        ),
      ]),
    );
  }
}

/// The items of one collection. Long-press takes one out.
class CollectionScreen extends StatelessWidget {
  final String name;
  const CollectionScreen({super.key, required this.name});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final p = LayoutPalette.of(context);
    final size = context.watch<SettingsState>().posterScale;
    final items = app.collectionItems(name);
    return Scaffold(
      appBar: AppBar(title: Text(name), backgroundColor: p.bg),
      body: items.isEmpty
          ? Center(
              child:
                  Text(tr('Nothing here yet.'), style: TextStyle(color: p.muted)))
          : GridView.builder(
              padding: const EdgeInsets.all(12),
              gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: 160 * size,
                  childAspectRatio: 2 / 3,
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 12),
              itemCount: items.length,
              itemBuilder: (_, i) => MediaTile(
                item: items[i],
                favorite: app.isFavorite(items[i]),
                onTap: () => openItem(context, items[i]),
                onLongPress: () {
                  app.toggleInCollection(name, items[i]);
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                      content: Text(trf('Removed "{item}" from {list}', {'item': items[i].name, 'list': name}))));
                },
              ),
            ),
    );
  }
}
