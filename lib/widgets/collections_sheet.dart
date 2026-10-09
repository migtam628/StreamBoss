import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../layouts/ui_layout.dart';
import '../models/media.dart';
import '../state/app_state.dart';

/// Asks for a name. Returns it, trimmed, or null when cancelled.
Future<String?> askCollectionName(BuildContext context,
    {String title = 'New collection', String initial = ''}) {
  final c = TextEditingController(text: initial);
  return showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: c,
        autofocus: true,
        maxLength: 30,
        textCapitalization: TextCapitalization.sentences,
        decoration: const InputDecoration(hintText: 'Friday movie night'),
        onSubmitted: (v) => Navigator.pop(ctx, v.trim()),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
        FilledButton(
            onPressed: () => Navigator.pop(ctx, c.text.trim()),
            child: const Text('Save')),
      ],
    ),
  );
}

/// Pick which collections [item] belongs to, or start a new one.
Future<void> showCollectionsSheet(BuildContext context, MediaItem item) {
  final pal = LayoutPalette.of(context);
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: pal.surface,
    constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.8, maxWidth: 560),
    builder: (sheet) => Consumer<AppState>(
      builder: (_, app, __) => SafeArea(
        child: ListView(shrinkWrap: true, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 6),
            child: Text('Add "${item.name}" to',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style:
                    const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
          ),
          for (final name in app.collections.keys)
            CheckboxListTile(
              value: app.inCollection(name, item),
              title: Text(name),
              subtitle: Text(
                  '${app.collections[name]!.length} item${app.collections[name]!.length == 1 ? '' : 's'}'),
              onChanged: (_) => app.toggleInCollection(name, item),
            ),
          ListTile(
            autofocus: app.collections.isEmpty,
            leading: const Icon(Icons.add),
            title: const Text('New collection'),
            onTap: () async {
              final n = await askCollectionName(sheet);
              if (n == null || n.isEmpty) return;
              if (!app.createCollection(n)) {
                if (sheet.mounted) {
                  ScaffoldMessenger.maybeOf(sheet)?.showSnackBar(
                      const SnackBar(content: Text('That name is taken.')));
                }
                return;
              }
              app.toggleInCollection(n, item);
            },
          ),
        ]),
      ),
    ),
  );
}
