import 'package:flutter/material.dart';
import '../layouts/ui_layout.dart';
import '../services/voice_input.dart';

/// Overridden in tests.
VoiceInput Function() makeVoiceInput = SpeechVoiceInput.new;

/// Listens, shows the words as they come in, and returns the final words (null if cancelled or nothing
/// was heard). Shows why when voice search cannot start.
Future<String?> askByVoice(BuildContext context) {
  return showDialog<String>(
    context: context,
    barrierDismissible: false,
    builder: (_) => const _VoiceDialog(),
  );
}

class _VoiceDialog extends StatefulWidget {
  const _VoiceDialog();

  @override
  State<_VoiceDialog> createState() => _VoiceDialogState();
}

class _VoiceDialogState extends State<_VoiceDialog> {
  late final VoiceInput _input = makeVoiceInput();
  String _words = '';
  String? _problem;
  bool _done = false;

  @override
  void initState() {
    super.initState();
    _begin();
  }

  Future<void> _begin() async {
    final ok = await _input.start(
      onWords: (w, done) {
        if (!mounted || _done) return;
        setState(() => _words = w);
        if (done) _finish(w);
      },
      onError: (m) {
        if (!mounted || _done) return;
        setState(() => _problem = m);
      },
    );
    if (!ok && mounted && _problem == null) setState(() => _problem = 'Voice search is not available on this device.');
  }

  void _finish(String w) {
    if (_done) return;
    _done = true;
    Navigator.of(context).pop(w.trim().isEmpty ? null : w.trim());
  }

  @override
  void dispose() {
    _input.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = LayoutPalette.of(context);
    return AlertDialog(
      title: Row(children: [
        Icon(_problem == null ? Icons.mic : Icons.mic_off, color: _problem == null ? p.accent : p.muted),
        const SizedBox(width: 10),
        Text(_problem == null ? 'Listening…' : 'Voice search'),
      ]),
      content: SizedBox(
        width: 420,
        child: Text(
          _problem ?? (_words.isEmpty ? 'Say a title or a channel name.' : _words),
          style: TextStyle(fontSize: _problem == null && _words.isNotEmpty ? 22 : 16, color: _problem == null ? p.text : p.muted),
        ),
      ),
      actions: [
        TextButton(autofocus: _problem != null, onPressed: () => _finish(''), child: Text(_problem == null ? 'Cancel' : 'Close')),
        if (_problem == null)
          FilledButton(
            autofocus: true,
            onPressed: () async {
              await _input.stop();
              // The final result normally arrives from stop(); if it does not, use what was heard.
              await Future<void>.delayed(const Duration(milliseconds: 400));
              if (mounted) _finish(_words);
            },
            child: const Text('Done'),
          ),
      ],
    );
  }
}

/// A microphone button for a search field: hears a phrase and hands it to [onWords].
class VoiceButton extends StatelessWidget {
  final ValueChanged<String> onWords;
  const VoiceButton({super.key, required this.onWords});

  @override
  Widget build(BuildContext context) {
    if (!voiceSearchPlatform) return const SizedBox.shrink();
    return IconButton(
      tooltip: 'Search by voice',
      icon: Icon(Icons.mic_none, color: LayoutPalette.of(context).muted),
      onPressed: () async {
        final w = await askByVoice(context);
        if (w != null && context.mounted) onWords(w);
      },
    );
  }
}
