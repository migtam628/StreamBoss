import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/self_update.dart';
import '../services/update_check.dart';
import '../state/settings_state.dart';

/// "Version X is available": shows what changed, then downloads the update and installs it without
/// leaving the app. Android hands the file to the system installer (it asks once to allow installs from
/// StreamBoss); the desktop apps quit, swap their files and start again.
Future<void> showUpdateDialog(BuildContext context, UpdateInfo u, String current) => showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => UpdateDialog(update: u, current: current),
    );

enum _Phase { ready, permission, downloading, installing, failed, unsupported }

class UpdateDialog extends StatefulWidget {
  final UpdateInfo update;
  final String current;

  /// For tests: how the file is fetched and handed over.
  final Future<File> Function(UpdateAsset, void Function(int, int), UpdateCancel)? download;
  final Future<void> Function(File, UpdateTarget)? install;
  final UpdateTarget? target;
  final List<String>? abis;
  const UpdateDialog({
    super.key,
    required this.update,
    required this.current,
    this.download,
    this.install,
    this.target,
    this.abis,
  });

  @override
  State<UpdateDialog> createState() => _UpdateDialogState();
}

/// The release notes without the markdown marks, short enough for a dialog.
String plainNotes(String md, {int max = 900}) {
  var t = md
      .replaceAll('\r', '')
      .replaceAllMapped(RegExp(r'\[([^\]]+)\]\([^)]+\)'), (m) => m[1]!)
      .replaceAll(RegExp(r'[*_`#]+'), '')
      .replaceAll(RegExp(r'\n{3,}'), '\n\n')
      .trim();
  if (t.length > max) t = '${t.substring(0, max).trimRight()}…';
  return t;
}

class _UpdateDialogState extends State<UpdateDialog> {
  _Phase _phase = _Phase.ready;
  String _error = '';
  int _got = 0, _total = 0;
  final _cancel = UpdateCancel();
  StreamSubscription<InstallEvent>? _sub;
  late final UpdateTarget? _target = widget.target ?? updateTarget();
  bool _waitingOnAndroid = false;

  @override
  void initState() {
    super.initState();
    if (_target == null) _phase = _Phase.unsupported;
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  String _mb(int b) => (b / 1048576).toStringAsFixed(1);

  Future<void> _go() async {
    final t = _target;
    if (t == null) return;
    setState(() {
      _error = '';
      _phase = _Phase.downloading;
      _got = 0;
      _total = 0;
    });
    try {
      final abis = widget.abis ?? (t == UpdateTarget.android ? await SelfUpdate.abis() : const <String>[]);
      final asset = pickAsset(widget.update.assets, t, abis: abis);
      if (asset == null) throw Exception('This release has no download for this device yet.');
      if (t == UpdateTarget.android && widget.install == null && !await SelfUpdate.canInstall()) {
        if (mounted) setState(() => _phase = _Phase.permission);
        return;
      }
      void progress(int g, int total) {
        if (mounted) {
          setState(() {
            _got = g;
            _total = total;
          });
        }
      }

      final file = widget.download != null
          ? await widget.download!(asset, progress, _cancel)
          : await downloadUpdate(asset,
              dir: await SelfUpdate.downloadDir(), onProgress: progress, cancel: _cancel);
      if (!mounted) return;
      setState(() => _phase = _Phase.installing);
      if (t == UpdateTarget.android) {
        context.read<SettingsState>().set('updating', true, notify: false);
        _sub ??= SelfUpdate.events.listen(_onInstall);
      }
      await (widget.install ?? SelfUpdate.install)(file, t);
    } on UpdateCancelled {
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      if (_target == UpdateTarget.android) context.read<SettingsState>().set('updating', false, notify: false);
      setState(() {
        _error = e.toString().replaceFirst('Exception: ', '');
        _phase = _Phase.failed;
      });
    }
  }

  void _onInstall(InstallEvent e) {
    if (!mounted) return;
    switch (e.status) {
      case InstallStatus.waiting:
        setState(() => _waitingOnAndroid = true);
      case InstallStatus.success:
        Navigator.of(context).pop();
      case InstallStatus.failed:
        context.read<SettingsState>().set('updating', false, notify: false);
        setState(() {
          _error = e.message ?? 'The install failed.';
          _phase = _Phase.failed;
        });
    }
  }

  @override
  Widget build(BuildContext context) {
    final u = widget.update;
    final notes = plainNotes(u.notes);
    Widget body;
    List<Widget> actions;
    switch (_phase) {
      case _Phase.ready:
        body = Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('You have ${widget.current}. The update is downloaded and installed here, without opening a browser.'),
          if (notes.isNotEmpty) ...[
            const SizedBox(height: 12),
            const Text("What's new", style: TextStyle(fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 220),
              child: SingleChildScrollView(child: Text(notes, style: const TextStyle(fontSize: 13, height: 1.35))),
            ),
          ],
        ]);
        actions = [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Later')),
          FilledButton(autofocus: true, onPressed: _go, child: const Text('Update now')),
        ];
      case _Phase.permission:
        body = const Text('Android asks you to allow StreamBoss to install apps, once. Turn on "Allow from this source" '
            'on the next screen, press Back to return here, then tap Continue.');
        actions = [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          const TextButton(onPressed: SelfUpdate.openInstallSettings, child: Text('Open settings')),
          FilledButton(autofocus: true, onPressed: _go, child: const Text('Continue')),
        ];
      case _Phase.downloading:
        body = Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Downloading ${u.latest}'),
          const SizedBox(height: 12),
          LinearProgressIndicator(value: _total > 0 ? _got / _total : null),
          const SizedBox(height: 6),
          Text(_total > 0 ? '${_mb(_got)} of ${_mb(_total)} MB' : '${_mb(_got)} MB', style: const TextStyle(fontSize: 12)),
        ]);
        actions = [TextButton(autofocus: true, onPressed: _cancel.cancel, child: const Text('Cancel'))];
      case _Phase.installing:
        body = Row(children: [
          const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 3)),
          const SizedBox(width: 16),
          Expanded(
            child: Text(_target == UpdateTarget.android
                ? (_waitingOnAndroid
                    ? 'Confirm the install on the screen Android shows. StreamBoss reopens when it is done.'
                    : 'Handing the update to Android…')
                : 'Installing. StreamBoss closes and opens again by itself.'),
          ),
        ]);
        actions = _target == UpdateTarget.android
            ? [TextButton(autofocus: true, onPressed: () => Navigator.pop(context), child: const Text('Close'))]
            : const [];
      case _Phase.failed:
        body = Text('The update did not install.\n$_error');
        actions = [
          TextButton(autofocus: true, onPressed: () => Navigator.pop(context), child: const Text('Close')),
          FilledButton(onPressed: _go, child: const Text('Try again')),
        ];
      case _Phase.unsupported:
        body = const Text('This version of StreamBoss is updated by whatever installed it (the web page itself, or the '
            'App Store / TestFlight on Apple devices), not from inside the app.');
        actions = [FilledButton(autofocus: true, onPressed: () => Navigator.pop(context), child: const Text('Close'))];
    }
    return AlertDialog(
      title: Text('Version ${u.latest} is available'),
      content: SizedBox(width: 520, child: body),
      actions: actions,
    );
  }
}
