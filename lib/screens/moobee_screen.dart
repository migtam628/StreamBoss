import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, visibleForTesting;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';
import '../l10n/l10n.dart';
import '../layouts/ui_layout.dart';
import '../services/moobee.dart';
import '../state/settings_state.dart';

/// MooBee, the movie and TV discovery site, inside the app. On Android, iOS and macOS it is a web view with back,
/// reload and "open in browser"; Windows, Linux and the web app show a button that opens it in the browser.
class MooBeeScreen extends StatefulWidget {
  /// For tests: whether to use the in-app web view (null follows the platform).
  @visibleForTesting
  final bool? inApp;
  const MooBeeScreen({super.key, this.inApp});

  @override
  State<MooBeeScreen> createState() => _MooBeeScreenState();
}

class _MooBeeScreenState extends State<MooBeeScreen> {
  WebViewController? _web;
  Uri? _home;
  bool _loading = true, _canGoBack = false, _failed = false;

  bool get _inApp =>
      widget.inApp ?? moobeeInApp(web: kIsWeb, platform: defaultTargetPlatform);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final home = moobeeAddress(context.read<SettingsState>().moobeeUrl);
    if (home == _home) return;
    _home = home;
    if (_inApp && home != null) {
      final c = WebViewController()
        ..setJavaScriptMode(JavaScriptMode.unrestricted)
        ..setBackgroundColor(const Color(0xFF0B0B0F))
        ..setNavigationDelegate(NavigationDelegate(
          onNavigationRequest: (r) {
            final u = Uri.tryParse(r.url);
            if (u == null || moobeeOwnPage(home, u)) {
              return NavigationDecision.navigate;
            }
            launchUrl(u,
                mode: LaunchMode
                    .externalApplication); // a link out of MooBee opens in the browser
            return NavigationDecision.prevent;
          },
          onPageStarted: (_) {
            if (mounted) setState(() => _loading = true);
          },
          onPageFinished: (_) async {
            final back = await _web?.canGoBack() ?? false;
            if (mounted) {
              setState(() {
                _loading = false;
                _canGoBack = back;
              });
            }
          },
          onWebResourceError: (e) {
            if ((e.isForMainFrame ?? true) && mounted) {
              setState(() {
                _failed = true;
                _loading = false;
              });
            }
          },
        ))
        ..loadRequest(home);
      _web = c;
      _failed = false;
    }
  }

  Future<void> _back() async {
    final w = _web;
    if (w == null) return;
    await w.goBack();
    final b = await w.canGoBack();
    if (mounted) setState(() => _canGoBack = b);
  }

  void _open() {
    final h = _home;
    if (h != null) launchUrl(h, mode: LaunchMode.externalApplication);
  }

  void _retry() {
    final h = _home;
    if (h == null) return;
    setState(() {
      _failed = false;
      _loading = true;
    });
    _web?.loadRequest(h);
  }

  @override
  Widget build(BuildContext context) {
    final p = LayoutPalette.of(context);
    final home = _home;
    if (home == null) {
      return _Card(
        icon: Icons.link_off,
        title: tr('MooBee has no address'),
        text: tr('Check the MooBee address in Settings > Appearance.'),
      );
    }
    final web = _web;
    if (!_inApp || web == null) {
      return _Card(
        icon: Icons.explore_outlined,
        title: 'MooBee',
        text: tr(
            'Find movies and shows to watch. It opens in your browser on this device.'),
        action: FilledButton.icon(
            onPressed: _open,
            icon: const Icon(Icons.open_in_new),
            label: Text(tr('Open MooBee'))),
      );
    }
    return PopScope(
      canPop: !_canGoBack,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _back();
      },
      child: Column(children: [
        SizedBox(
          height: 44,
          child: Row(children: [
            const SizedBox(width: 8),
            IconButton(
                icon: Icon(Icons.arrow_back,
                    color: _canGoBack ? p.text : p.muted),
                tooltip: tr('Back'),
                onPressed: _canGoBack ? _back : null),
            IconButton(
                icon: Icon(Icons.refresh, color: p.text),
                tooltip: tr('Reload'),
                onPressed: _retry),
            Expanded(
                child: Text('MooBee',
                    style: TextStyle(
                        color: p.muted, fontWeight: FontWeight.w700))),
            IconButton(
                icon: Icon(Icons.open_in_new, color: p.text),
                tooltip: tr('Open in browser'),
                onPressed: _open),
            const SizedBox(width: 8),
          ]),
        ),
        if (_loading) const LinearProgressIndicator(minHeight: 2),
        Expanded(
          child: _failed
              ? _Card(
                  icon: Icons.cloud_off,
                  title: tr('MooBee did not load'),
                  text: tr('Check your connection, then try again.'),
                  action: FilledButton.icon(
                      onPressed: _retry,
                      icon: const Icon(Icons.refresh),
                      label: Text(tr('Try again'))),
                )
              : WebViewWidget(controller: web),
        ),
      ]),
    );
  }
}

class _Card extends StatelessWidget {
  final IconData icon;
  final String title, text;
  final Widget? action;
  const _Card(
      {required this.icon,
      required this.title,
      required this.text,
      this.action});

  @override
  Widget build(BuildContext context) {
    final p = LayoutPalette.of(context);
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 44, color: p.accent),
            const SizedBox(height: 14),
            Text(title,
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: p.text, fontSize: 20, fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            Text(text,
                textAlign: TextAlign.center,
                style: TextStyle(color: p.muted, height: 1.4)),
            if (action != null) ...[const SizedBox(height: 18), action!],
          ]),
        ),
      ),
    );
  }
}
