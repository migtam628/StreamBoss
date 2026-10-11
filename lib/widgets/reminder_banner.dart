import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../layouts/ui_layout.dart';
import '../models/media.dart';
import '../screens/open_item.dart';
import '../screens/player_screen.dart';
import '../services/nav_guard.dart';
import '../services/mini_player.dart';
import '../services/reminders.dart';
import '../state/app_state.dart';
import '../l10n/l10n.dart';

/// Opens the live channel [key] on the app's navigator. False when the channel is no longer in the library.
bool openReminderChannel(AppState app, String key) {
  final ctx = MiniPlayer.navigatorKey.currentContext;
  if (ctx == null) return false;
  final live = app.shown.live;
  final ch = live.where((c) => c.key == key).firstOrNull ?? app.catalog.live.where((c) => c.key == key).firstOrNull;
  if (ch == null || ch.kind != MediaKind.live) return false;
  openItem(ctx, ch, queue: live);
  return true;
}

/// Plays the title chosen in the Android TV "Continue watching" row, from where it stopped. False when it is
/// not in the history any more (another profile, or cleared).
bool openResumeTitle(AppState app, String key) {
  final ctx = MiniPlayer.navigatorKey.currentContext;
  final item = app.recents.where((e) => e.key == key).firstOrNull;
  if (ctx == null || item == null || item.streamUrl == null || !NavGuard.allow()) return false;
  Navigator.of(ctx).push(MaterialPageRoute(
      builder: (_) => PlayerScreen(title: item.name, url: item.streamUrl!, item: item, startAt: app.resumeFor(item))));
  return true;
}

/// The app-wide part of reminders: a banner when a programme is about to start (it works on every
/// platform, TV included), and opening the channel when a reminder notification was tapped.
class ReminderHost extends StatefulWidget {
  const ReminderHost({super.key});

  @override
  State<ReminderHost> createState() => _ReminderHostState();
}

class _ReminderHostState extends State<ReminderHost> {
  Timer? _hide;

  @override
  void dispose() {
    _hide?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final pending = app.pendingOpenChannel;
    if (pending != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final a = context.read<AppState>();
        if (a.pendingOpenChannel != pending) return;
        // Wait for the library when the app was started by the notification and has not loaded it yet.
        if (openReminderChannel(a, pending) || a.catalog.live.isNotEmpty) a.pendingOpenChannel = null;
      });
    }
    final resume = app.pendingResumeKey;
    if (resume != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final a = context.read<AppState>();
        if (a.pendingResumeKey != resume) return;
        a.pendingResumeKey = null;
        openResumeTitle(a, resume);
      });
    }
    final r = app.bannerReminder;
    if (r == null) return const SizedBox.shrink();
    _hide?.cancel();
    _hide = Timer(const Duration(seconds: 60), () {
      if (mounted) context.read<AppState>().dismissBanner();
    });
    final p = LayoutPalette.of(context);
    return SafeArea(
      child: Align(
        alignment: Alignment.topCenter,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Material(
            color: p.surface,
            elevation: 8,
            borderRadius: BorderRadius.circular(14),
            child: Container(
              constraints: const BoxConstraints(maxWidth: 560),
              padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
              decoration: BoxDecoration(border: Border.all(color: p.accent, width: 2), borderRadius: BorderRadius.circular(14)),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.notifications_active, color: p.accent),
                const SizedBox(width: 12),
                Flexible(
                  child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(r.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: p.text, fontWeight: FontWeight.w800, fontSize: 16)),
                    Text('${startsIn(r)}  ·  ${r.channelName}', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: p.muted, fontSize: 13)),
                  ]),
                ),
                const SizedBox(width: 12),
                FilledButton(
                  autofocus: true,
                  onPressed: () {
                    final a = context.read<AppState>();
                    a.dismissBanner();
                    openReminderChannel(a, r.channelKey);
                  },
                  child: Text(tr('Watch')),
                ),
                const SizedBox(width: 6),
                IconButton(
                  tooltip: tr('Dismiss'),
                  icon: Icon(Icons.close, color: p.muted),
                  onPressed: () => context.read<AppState>().dismissBanner(),
                ),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}
