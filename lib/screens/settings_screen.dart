import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../state/app_state.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    return ListView(children: [
      ListTile(
        leading: const Icon(Icons.dns),
        title: Text('Source: ${s.active?.name ?? '-'}'),
        subtitle: Text(
            '${s.catalog.live.length} channels · ${s.catalog.movies.length} movies · ${s.catalog.series.length} series'),
      ),
      ListTile(
        leading: const Icon(Icons.refresh),
        title: const Text('Reload library'),
        onTap: () => s.active == null ? null : s.activate(s.active!),
      ),
      ListTile(
        leading: const Icon(Icons.swap_horiz),
        title: const Text('Switch source'),
        onTap: s.signOut,
      ),
      const ListTile(
        leading: Icon(Icons.info_outline),
        title: Text('StreamBoss is a player only'),
        subtitle: Text('No content is included. Use a service you are licensed to watch.'),
      ),
    ]);
  }
}
