import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';
import '../state/sync_state.dart';

/// Syncs when the app comes back, and when it is put away (the last chance before the system may stop it).
class SyncHost extends StatefulWidget {
  const SyncHost({super.key});

  @override
  State<SyncHost> createState() => _SyncHostState();
}

class _SyncHostState extends State<SyncHost> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed ||
        state == AppLifecycleState.paused) {
      context.read<SyncState>().lifecycle();
    }
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
