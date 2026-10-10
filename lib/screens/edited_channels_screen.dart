import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../layouts/ui_layout.dart';
import '../state/app_state.dart';
import 'settings/settings_widgets.dart' show confirmDialog;

/// Settings > Library > Edited channels: every channel that was renamed, hidden or pinned, with a way
/// to undo each one. A hidden channel is not in any list, so this is where it comes back.
class EditedChannelsScreen extends StatelessWidget {
  const EditedChannelsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final p = LayoutPalette.of(context);
    final e = s.channelEdits;
    final keys = [
      ...e.pins,
      for (final k in e.edits.keys)
        if (!e.pins.contains(k)) k,
    ];

    String nameOf(String key) {
      final ed = e.edits[key];
      return ed?.name ?? ed?.original ?? s.itemByKey(key)?.name ?? key;
    }

    String statusOf(String key) {
      final ed = e.edits[key];
      return [
        if (e.pins.contains(key)) 'Pinned (${e.pins.indexOf(key) + 1})',
        if (ed?.hidden ?? false) 'Hidden',
        if (ed?.name != null) 'Was "${ed!.original}"',
      ].join('  ·  ');
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Edited channels'),
        backgroundColor: p.bg,
        actions: [
          if (keys.isNotEmpty)
            TextButton(
              onPressed: () async {
                if (await confirmDialog(context, title: 'Undo every change?', body: 'Renamed, hidden and pinned channels go back to how the provider lists them.', confirm: 'Undo all')) {
                  s.resetAllChannelEdits();
                }
              },
              child: const Text('Undo all'),
            ),
        ],
      ),
      body: keys.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text('No channel has been changed. Press and hold a channel to rename it, hide it or pin it to the top.',
                    textAlign: TextAlign.center, style: TextStyle(color: p.muted, height: 1.4)),
              ),
            )
          : ListView(children: [
              for (final k in keys)
                ListTile(
                  leading: Icon((e.edits[k]?.hidden ?? false) ? Icons.visibility_off_outlined : (e.pins.contains(k) ? Icons.push_pin : Icons.edit_outlined)),
                  title: Text(nameOf(k)),
                  subtitle: Text(statusOf(k)),
                  trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                    if (e.pins.contains(k) && e.pins.indexOf(k) > 0)
                      IconButton(tooltip: 'Move up', icon: const Icon(Icons.arrow_upward), onPressed: () => s.movePinned(k, -1)),
                    if (e.pins.contains(k) && e.pins.indexOf(k) < e.pins.length - 1)
                      IconButton(tooltip: 'Move down', icon: const Icon(Icons.arrow_downward), onPressed: () => s.movePinned(k, 1)),
                    TextButton(onPressed: () => s.resetChannel(k), child: const Text('Undo')),
                  ]),
                ),
            ]),
    );
  }
}
