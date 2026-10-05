import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../state/app_state.dart';
import '../state/settings_state.dart';
import '../theme.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  static const _colors = [0xFFFFFFFF, 0xFFFFEB3B, 0xFF00E5FF, 0xFF76FF03];

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final st = context.watch<SettingsState>();

    Widget header(String t) => Padding(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
          child: Text(t.toUpperCase(),
              style: const TextStyle(color: Boss.accent, fontWeight: FontWeight.w700, letterSpacing: 1.5, fontSize: 12)),
        );

    return ListView(children: [
      header('Source'),
      ListTile(
        leading: const Icon(Icons.dns),
        title: Text(s.active?.name ?? '-'),
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

      header('Playback'),
      ListTile(
        leading: const Icon(Icons.memory),
        title: const Text('Decoder'),
        trailing: SegmentedButton<String>(
          segments: const [
            ButtonSegment(value: 'auto', label: Text('Hardware')),
            ButtonSegment(value: 'software', label: Text('Software')),
          ],
          selected: {st.decoder},
          onSelectionChanged: (v) => st.update(decoder: v.first),
        ),
      ),
      ListTile(
        leading: const Icon(Icons.network_check),
        title: const Text('Network buffer'),
        subtitle: const Text('Higher = fewer stalls on weak connections, slower channel start'),
        trailing: SegmentedButton<int>(
          segments: const [
            ButtonSegment(value: 5, label: Text('Low')),
            ButtonSegment(value: 20, label: Text('Normal')),
            ButtonSegment(value: 60, label: Text('High')),
          ],
          selected: {st.bufferSecs},
          onSelectionChanged: (v) => st.update(bufferSecs: v.first),
        ),
      ),
      ListTile(
        leading: const Icon(Icons.speed),
        title: Text('Default movie speed: ${st.speed}x'),
        subtitle: Slider(
          value: st.speed,
          min: 0.5,
          max: 2,
          divisions: 6,
          activeColor: Boss.accent,
          onChanged: (v) => st.update(speed: v),
        ),
      ),

      header('Subtitles'),
      // Live preview, like mpvNova's subtitle styling screen.
      Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        height: 90,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: Boss.surfaceHi,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          'The quick brown fox jumps over the lazy dog',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: st.subSize * 0.6,
            color: Color(st.subColor),
            backgroundColor: st.subBackground ? const Color(0xAA000000) : null,
          ),
        ),
      ),
      ListTile(
        title: Text('Size: ${st.subSize.round()}'),
        subtitle: Slider(
          value: st.subSize,
          min: 20,
          max: 64,
          activeColor: Boss.accent,
          onChanged: (v) => st.update(subSize: v),
        ),
      ),
      ListTile(
        title: const Text('Color'),
        trailing: Row(mainAxisSize: MainAxisSize.min, children: [
          for (final c in _colors)
            Padding(
              padding: const EdgeInsets.only(left: 8),
              child: InkResponse(
                onTap: () => st.update(subColor: c),
                child: CircleAvatar(
                  radius: 14,
                  backgroundColor: Color(c),
                  child: st.subColor == c ? const Icon(Icons.check, size: 16, color: Colors.black) : null,
                ),
              ),
            ),
        ]),
      ),
      SwitchListTile(
        title: const Text('Background box'),
        value: st.subBackground,
        activeThumbColor: Boss.accent,
        onChanged: (v) => st.update(subBackground: v),
      ),

      header('Metadata'),
      ListTile(
        leading: const Icon(Icons.movie_filter),
        title: const Text('TMDB API key'),
        subtitle: Text(st.tmdbKey.isEmpty
            ? 'Not set. Add a free key from themoviedb.org for posters, cast and trailers.'
            : 'Key saved'),
        onTap: () async {
          final c = TextEditingController(text: st.tmdbKey);
          final v = await showDialog<String>(
            context: context,
            builder: (ctx) => AlertDialog(
              title: const Text('TMDB API key (v3)'),
              content: TextField(controller: c, autofocus: true),
              actions: [
                TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
                FilledButton(onPressed: () => Navigator.pop(ctx, c.text.trim()), child: const Text('Save')),
              ],
            ),
          );
          if (v != null) st.update(tmdbKey: v);
        },
      ),

      header('About'),
      const ListTile(
        leading: Icon(Icons.info_outline),
        title: Text('StreamBoss is a player only'),
        subtitle: Text('No content is included. Use a service you are licensed to watch.'),
      ),
    ]);
  }
}
