import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../layouts/common.dart';
import '../layouts/ui_layout.dart';
import '../models/media.dart';
import '../services/search.dart' show normalizeSearch;
import '../state/app_state.dart';
import '../state/settings_state.dart';
import '../widgets/collections_sheet.dart';
import '../widgets/media_tile.dart';
import 'open_item.dart';
import 'settings/settings_widgets.dart' show confirmDialog;

/// My list and every collection in one place. Chips pick the list; a title can be moved to the top or
/// earlier and later in the order you keep it, or taken out. A to Z shows the same list sorted without
/// changing your order.
class MyListsScreen extends StatefulWidget {
  /// The collection to open first; null opens My list.
  final String? initial;
  const MyListsScreen({super.key, this.initial});

  @override
  State<MyListsScreen> createState() => _MyListsScreenState();
}

class _MyListsScreenState extends State<MyListsScreen> {
  String? _list; // null = My list
  bool _az = false;

  @override
  void initState() {
    super.initState();
    _list = widget.initial;
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final p = LayoutPalette.of(context);
    final size = context.watch<SettingsState>().posterScale;
    final names = s.collections.keys.toList();
    final list = names.contains(_list) ? _list : null;
    var items = list == null ? s.favoriteItems : s.collectionItems(list);
    if (_az) {
      items = [...items]..sort((a, b) => normalizeSearch(a.name).compareTo(normalizeSearch(b.name)));
    }

    Future<void> menu(MediaItem it) async {
      final i = items.indexOf(it);
      void move({bool top = false, int by = 0}) =>
          list == null ? s.moveFavorite(it.key, toTop: top, by: by) : s.moveInCollection(list, it.key, toTop: top, by: by);
      await showModalBottomSheet<void>(
        context: context,
        backgroundColor: p.surface,
        constraints: const BoxConstraints(maxWidth: 560),
        builder: (ctx) => SafeArea(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 8),
              child: Text(it.name, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: p.text)),
            ),
            if (!_az) ...[
              if (i > 0)
                ListTile(
                    leading: const Icon(Icons.vertical_align_top),
                    title: const Text('Move to the top'),
                    onTap: () {
                      Navigator.pop(ctx);
                      move(top: true);
                    }),
              if (i > 0)
                ListTile(
                    leading: const Icon(Icons.arrow_back),
                    title: const Text('Move earlier'),
                    onTap: () {
                      Navigator.pop(ctx);
                      move(by: -1);
                    }),
              if (i < items.length - 1)
                ListTile(
                    leading: const Icon(Icons.arrow_forward),
                    title: const Text('Move later'),
                    onTap: () {
                      Navigator.pop(ctx);
                      move(by: 1);
                    }),
            ],
            ListTile(
                leading: const Icon(Icons.close),
                title: Text(list == null ? 'Remove from My list' : 'Remove from $list'),
                onTap: () {
                  Navigator.pop(ctx);
                  if (list == null) {
                    s.toggleFavorite(it);
                  } else {
                    s.toggleInCollection(list, it);
                  }
                }),
          ]),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(list ?? 'My lists'),
        backgroundColor: p.bg,
        actions: [
          IconButton(
            tooltip: 'New list',
            icon: const Icon(Icons.add),
            onPressed: () async {
              final n = await askCollectionName(context);
              if (n == null || n.isEmpty) return;
              if (!s.createCollection(n)) {
                if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('That name is taken.')));
              } else {
                setState(() => _list = n);
              }
            },
          ),
          if (list != null)
            PopupMenuButton<String>(
              onSelected: (v) async {
                if (v == 'rename') {
                  final to = await askCollectionName(context, title: 'Rename list', initial: list);
                  if (to != null && to.isNotEmpty && to != list) {
                    if (s.renameCollection(list, to)) {
                      setState(() => _list = to);
                    } else if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('That name is taken.')));
                    }
                  }
                } else if (v == 'delete') {
                  if (await confirmDialog(context, title: 'Delete "$list"?', body: 'The titles stay in your library.', confirm: 'Delete')) {
                    s.deleteCollection(list);
                    setState(() => _list = null);
                  }
                }
              },
              itemBuilder: (_) => const [PopupMenuItem(value: 'rename', child: Text('Rename')), PopupMenuItem(value: 'delete', child: Text('Delete'))],
            ),
        ],
      ),
      body: Column(children: [
        ChipRow(
          labels: ['My list  ${s.favoriteItems.length}', for (final n in names) '$n  ${s.collectionItems(n).length}'],
          selected: list == null ? 0 : names.indexOf(list) + 1,
          onSelect: (i) => setState(() => _list = i == 0 ? null : names[i - 1]),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
          child: Row(children: [
            Text('Order:', style: TextStyle(color: p.muted)),
            const SizedBox(width: 8),
            for (final (label, az) in const [('Mine', false), ('A to Z', true)])
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: FocusSurface(
                  radius: 16,
                  semanticLabel: 'Order: $label',
                  onTap: () => setState(() => _az = az),
                  builder: (_, __) => Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    color: _az == az ? p.accent : p.wash(0.08),
                    child: Text(label, style: TextStyle(fontWeight: FontWeight.w700, color: _az == az ? p.onAccent : p.text)),
                  ),
                ),
              ),
            Expanded(
              child: Text('Press and hold a title to move it',
                  textAlign: TextAlign.end, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: p.muted, fontSize: 12)),
            ),
          ]),
        ),
        Expanded(
          child: items.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                        list == null
                            ? 'Nothing here yet. Press and hold a title, or choose My list on its page, to save it here.'
                            : 'Nothing here yet. Open a movie or series and choose Add to collection.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: p.muted)),
                  ),
                )
              : GridView.builder(
                  padding: const EdgeInsets.all(16),
                  gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                      maxCrossAxisExtent: 170 * size, childAspectRatio: 2 / 3, mainAxisSpacing: 12, crossAxisSpacing: 12),
                  itemCount: items.length,
                  itemBuilder: (_, i) => MediaTile(
                    item: items[i],
                    favorite: s.isFavorite(items[i]),
                    autofocus: i == 0,
                    onTap: () => openItem(context, items[i], queue: items[i].kind == MediaKind.live ? [for (final x in items) if (x.kind == MediaKind.live) x] : null),
                    onLongPress: () => menu(items[i]),
                  ),
                ),
        ),
      ]),
    );
  }
}
