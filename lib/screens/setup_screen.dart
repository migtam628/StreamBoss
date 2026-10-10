import 'package:flutter/material.dart';
import '../layouts/ui_layout.dart';
import 'package:provider/provider.dart';
import '../models/media.dart';
import '../services/http_client.dart';
import '../services/pairing.dart';
import '../services/provider_url.dart';
import '../state/app_state.dart';
import '../widgets/tv.dart';
import 'free_playlists_screen.dart';
import 'pairing_dialog.dart';
import '../widgets/tv_text_field.dart';

class SetupScreen extends StatefulWidget {
  const SetupScreen({super.key});

  @override
  State<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends State<SetupScreen> {
  SourceType _type = SourceType.xtream;
  final _name = TextEditingController(text: 'My Provider');
  final _url = TextEditingController();
  final _user = TextEditingController();
  final _pass = TextEditingController();

  /// Checks the address without logging in: DNS, each address, a connection and one request.
  /// Useful when "it won't load" could be the network, the address or the provider.
  Future<void> _test() async {
    var url = _url.text.trim();
    if (_type == SourceType.xtream) {
      final login = parseProviderLink(url);
      if (login != null) url = login.server;
    } else {
      url = url.split('\n').first.trim();
    }
    final uri = url.isEmpty ? null : Uri.tryParse(url.contains('://') ? url : 'http://$url');
    if (uri == null || uri.host.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Enter a server address first.')));
      return;
    }
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Connection to ${uri.host}'),
        content: FutureBuilder<String>(
          future: diagnoseConnection(uri, appHttp),
          builder: (_, snap) => snap.connectionState != ConnectionState.done
              ? const Row(children: [
                  SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2)),
                  SizedBox(width: 14),
                  Text('Checking...'),
                ])
              : SingleChildScrollView(
                  child: SelectableText(
                      snap.hasError ? 'The check failed: ${snap.error}' : snap.data ?? '',
                      style: const TextStyle(fontFamily: 'monospace', fontSize: 13, height: 1.4))),
        ),
        actions: [TextButton(autofocus: true, onPressed: () => Navigator.pop(ctx), child: const Text('Close'))],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: s.loading
                ? const Column(mainAxisSize: MainAxisSize.min, children: [
                    CircularProgressIndicator(),
                    SizedBox(height: 16),
                    Text('Loading your library…'),
                  ])
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text('STREAMBOSS',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              fontSize: 34,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 4,
                              color: LayoutPalette.of(context).accent)),
                      const SizedBox(height: 4),
                      Text('Bring your own provider. We just play it.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: LayoutPalette.of(context).muted)),
                      const SizedBox(height: 28),
                      // Typing a login with a remote is miserable, so offer to take it from a phone.
                      if (pairingSupported) ...[
                        FilledButton.tonalIcon(
                          autofocus: TvScope.of(context),
                          icon: const Icon(Icons.phone_android),
                          label: const Padding(padding: EdgeInsets.all(10), child: Text('Set up from your phone')),
                          onPressed: () async {
                            final src = await showPairingDialog(context);
                            if (src != null) s.addSource(src);
                          },
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          child: Text('or enter it here', textAlign: TextAlign.center, style: TextStyle(color: LayoutPalette.of(context).muted)),
                        ),
                      ],
                      if (s.error != null)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: Text(s.error!,
                              style: TextStyle(color: LayoutPalette.of(context).accent)),
                        ),
                      if (s.sources.isNotEmpty) ...[
                        for (final src in s.sources)
                          ListTile(
                            leading: const Icon(Icons.dns),
                            title: Text(src.name),
                            subtitle: Text(src.type.name),
                            onTap: () => s.activate(src),
                            trailing: IconButton(
                              icon: const Icon(Icons.delete_outline),
                              onPressed: () => s.removeSource(src),
                            ),
                          ),
                        const Divider(height: 32),
                      ],
                      SegmentedButton<SourceType>(
                        segments: const [
                          ButtonSegment(value: SourceType.xtream, label: Text('Xtream')),
                          ButtonSegment(value: SourceType.m3u, label: Text('M3U')),
                        ],
                        selected: {_type},
                        onSelectionChanged: (v) => setState(() => _type = v.first),
                      ),
                      const SizedBox(height: 16),
                      TvTextField(
                          controller: _name,
                          decoration: const InputDecoration(labelText: 'Name')),
                      const SizedBox(height: 12),
                      TvTextField(
                        controller: _url,
                        keyboardType: TextInputType.url,
                        decoration: InputDecoration(
                            labelText: _type == SourceType.xtream
                                ? 'Server URL (http://host:port)'
                                : 'Playlist URL (.m3u)'),
                      ),
                      if (_type == SourceType.xtream) ...[
                        const SizedBox(height: 12),
                        TvTextField(
                            controller: _user,
                            decoration: const InputDecoration(labelText: 'Username')),
                        const SizedBox(height: 12),
                        TvTextField(
                            controller: _pass,
                            obscureText: true,
                            decoration: const InputDecoration(labelText: 'Password')),
                      ],
                      const SizedBox(height: 20),
                      FilledButton(
                        onPressed: () {
                          var url = _url.text.trim();
                          var user = _user.text.trim();
                          var pass = _pass.text;
                          // A pasted get.php?username=..&password=.. link works in the Xtream form.
                          if (_type == SourceType.xtream) {
                            final login = parseProviderLink(url);
                            if (login != null) {
                              url = login.server;
                              if (user.isEmpty) user = login.username;
                              if (pass.isEmpty) pass = login.password;
                              _url.text = url;
                              _user.text = user;
                              _pass.text = pass;
                            }
                          }
                          s.addSource(Source(
                            name: _name.text.trim().isEmpty ? 'Source' : _name.text.trim(),
                            type: _type,
                            url: url,
                            username: user,
                            password: pass,
                          ));
                        },
                        child: const Padding(
                          padding: EdgeInsets.all(12),
                          child: Text('Connect'),
                        ),
                      ),
                      TextButton(
                        onPressed: _test,
                        child: const Text('Test connection'),
                      ),
                      TextButton(
                        onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const FreePlaylistsScreen())),
                        child: const Text('Browse free public channels'),
                      ),
                      TextButton(
                        onPressed: () => s.activate(Source.demo),
                        child: const Text('Try demo mode'),
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}
