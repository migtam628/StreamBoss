import 'dart:async';
import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../models/media.dart';
import '../services/pairing.dart';
import '../theme.dart';

/// Shows the "set up from your phone" screen. Resolves with the login the phone sent, or null
/// if the dialog was dismissed. [start] is overridable for tests.
Future<Source?> showPairingDialog(BuildContext context, {Future<PairingSession?> Function()? start}) =>
    showDialog<Source>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _PairingDialog(start: start ?? startPairing),
    );

class _PairingDialog extends StatefulWidget {
  final Future<PairingSession?> Function() start;
  const _PairingDialog({required this.start});

  @override
  State<_PairingDialog> createState() => _PairingDialogState();
}

class _PairingDialogState extends State<_PairingDialog> {
  PairingSession? _session;
  StreamSubscription<Source>? _sub;
  bool _failed = false;
  bool _closing = false;

  @override
  void initState() {
    super.initState();
    widget.start().then((s) {
      if (!mounted) {
        s?.close();
        return;
      }
      if (s == null) {
        setState(() => _failed = true);
        return;
      }
      setState(() => _session = s);
      _sub = s.sources.listen((src) {
        if (!_closing && mounted) {
          _closing = true;
          Navigator.of(context).pop(src);
        }
      });
    }, onError: (_) {
      if (mounted) setState(() => _failed = true);
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    _session?.close();
    super.dispose();
  }

  Widget _step(String n, Widget text) => Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          CircleAvatar(radius: 13, backgroundColor: Boss.accent, child: Text(n, style: const TextStyle(color: Colors.black, fontWeight: FontWeight.w800))),
          const SizedBox(width: 12),
          Expanded(child: text),
        ]),
      );

  @override
  Widget build(BuildContext context) {
    final s = _session;
    return AlertDialog(
      title: const Text('Set up from your phone'),
      content: SizedBox(
        width: 640,
        child: _failed
            ? const Text("This device has no home-network address to share. Connect it to your Wi-Fi or Ethernet and try again, or type the login here.")
            : s == null
                ? const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator()))
                : Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
                      child: QrImageView(data: s.url, size: 190, backgroundColor: Colors.white),
                    ),
                    const SizedBox(width: 24),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        _step('1', Text.rich(TextSpan(children: [
                          const TextSpan(text: 'On your phone (same Wi-Fi) scan the code or open\n'),
                          TextSpan(text: s.url, style: const TextStyle(fontWeight: FontWeight.w700, color: Boss.accent2)),
                        ]))),
                        _step('2', Text.rich(TextSpan(children: [
                          const TextSpan(text: 'Enter the PIN  '),
                          TextSpan(text: s.pin, style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800, letterSpacing: 6)),
                        ]))),
                        _step('3', const Text('Fill in your login and tap Send to TV.')),
                        const Text('Your login travels over your home network only.', style: TextStyle(color: Boss.muted, fontSize: 12)),
                      ]),
                    ),
                  ]),
      ),
      actions: [
        TextButton(autofocus: true, onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
      ],
    );
  }
}
