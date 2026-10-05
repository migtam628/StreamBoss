import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/crash_report.dart';
import '../theme.dart';

/// Tells the user the last playback session ended abnormally, and shows the end of its log
/// (readable on a TV, copyable elsewhere). [switchedToSafe] says safe playback was just turned on.
Future<void> showCrashNotice(BuildContext context, CrashReport r, {required bool switchedToSafe, required bool wasSafeAlready}) {
  final String what;
  if (r.duringStartup) {
    what = switchedToSafe
        ? 'StreamBoss closed while starting playback, so Safe playback is now on: software decoding, which is slower but works on more devices. '
            'You can change it in Settings > Playback > Decoder.'
        : wasSafeAlready
            ? 'StreamBoss closed while starting playback, even with software decoding.'
            : 'StreamBoss closed while starting playback.';
  } else {
    what = 'StreamBoss closed unexpectedly during playback (step: ${r.lastStep}). Nothing was changed.';
  }
  return showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Playback closed unexpectedly'),
      content: SizedBox(
        width: 640,
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(what),
          const SizedBox(height: 12),
          const Text('Last recorded:', style: TextStyle(color: Boss.muted, fontSize: 12)),
          const SizedBox(height: 4),
          Flexible(
            child: SingleChildScrollView(
              child: SelectableText(r.tail(), style: const TextStyle(fontFamily: 'monospace', fontSize: 11, height: 1.35)),
            ),
          ),
        ]),
      ),
      actions: [
        TextButton(
          onPressed: () async {
            await Clipboard.setData(ClipboardData(text: r.text));
            if (ctx.mounted) ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(content: Text('Copied')));
          },
          child: const Text('Copy log'),
        ),
        FilledButton(autofocus: true, onPressed: () => Navigator.pop(ctx), child: const Text('OK')),
      ],
    ),
  );
}
