import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/media.dart';
import '../services/provider_url.dart';
import '../state/app_state.dart';
import '../theme.dart';

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
                      const Text('STREAMBOSS',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              fontSize: 34,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 4,
                              color: Boss.accent)),
                      const SizedBox(height: 4),
                      const Text('Bring your own provider. We just play it.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Boss.muted)),
                      const SizedBox(height: 28),
                      if (s.error != null)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: Text(s.error!,
                              style: const TextStyle(color: Boss.accent)),
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
                      TextField(
                          controller: _name,
                          decoration: const InputDecoration(labelText: 'Name')),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _url,
                        keyboardType: TextInputType.url,
                        decoration: InputDecoration(
                            labelText: _type == SourceType.xtream
                                ? 'Server URL (http://host:port)'
                                : 'Playlist URL (.m3u)'),
                      ),
                      if (_type == SourceType.xtream) ...[
                        const SizedBox(height: 12),
                        TextField(
                            controller: _user,
                            decoration: const InputDecoration(labelText: 'Username')),
                        const SizedBox(height: 12),
                        TextField(
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
