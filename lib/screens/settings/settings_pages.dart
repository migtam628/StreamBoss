import 'dart:convert';
import 'package:flutter/foundation.dart' show defaultTargetPlatform, kIsWeb;
import 'package:flutter/material.dart';
import '../../layouts/ui_layout.dart';
import '../../layouts/layout_picker.dart';
import '../free_playlists_screen.dart';
import '../onboarding_screen.dart';
import 'package:flutter/services.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../app_info.dart';
import '../../models/media.dart';
import '../../services/crash_guard.dart';
import '../../services/http_client.dart';
import '../../services/mpv_props.dart';
import '../../services/net_config.dart';
import '../../services/update_check.dart';
import '../../state/app_state.dart';
import '../../state/settings_state.dart';
import '../shader_screen.dart';
import 'settings_widgets.dart';

class SettingsSection {
  final String title;
  final String subtitle;
  final IconData icon;
  final WidgetBuilder builder;
  const SettingsSection(this.title, this.subtitle, this.icon, this.builder);
}

/// Every settings page, in display order.
final settingsSections = <SettingsSection>[
  SettingsSection('Source & library', 'Provider, reload, saved sources', Icons.dns, (_) => const SourcePage()),
  SettingsSection('Playback', 'Resume, seeking, languages, decoder', Icons.play_circle_outline, (_) => const PlaybackPage()),
  SettingsSection('Subtitles', 'Size, color, position', Icons.subtitles_outlined, (_) => const SubtitlesPage()),
  SettingsSection('Appearance', 'Text size, posters, start screen', Icons.palette_outlined, (_) => const AppearancePage()),
  SettingsSection('Library & guide', 'Filters, sorting, clock', Icons.video_library_outlined, (_) => const LibraryPage()),
  SettingsSection('Network & metadata', 'User-Agent, TMDB', Icons.public, (_) => const NetworkPage()),
  SettingsSection('Data & backup', 'Backup, history, reset', Icons.storage_outlined, (_) => const DataPage()),
  SettingsSection('About', 'Version, updates, support', Icons.info_outline, (_) => const AboutPage()),
];

// ---------------------------------------------------------------------------------------

class SourcePage extends StatelessWidget {
  const SourcePage({super.key});

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final lib = s.catalog;
    final hidden = lib.all.length - s.shown.all.length;
    final active = s.active;
    final type = active == null
        ? '-'
        : active.type == SourceType.m3u && s.usingXtreamApi
            ? 'M3U link (using the provider\'s Xtream API)'
            : active.type.name.toUpperCase();

    return ListView(children: [
      const SettingsHeader('Current source'),
      ListTile(
        isThreeLine: true,
        leading: const Icon(Icons.dns),
        title: Text(active?.name ?? 'None'),
        subtitle: Text('$type\n${lib.live.length} channels · ${lib.movies.length} movies · '
            '${lib.series.length} series${hidden > 0 ? ' · $hidden hidden by filter' : ''}'),
      ),
      if (s.account != null)
        ListTile(
          isThreeLine: true,
          leading: Icon(Icons.verified_user_outlined,
              color: (s.account!.daysLeft() ?? 999) <= 7 ? LayoutPalette.of(context).accent2 : null),
          title: const Text('Account'),
          subtitle: Text(s.account!.describe().join('\n')),
        ),
      ActionRow(
        icon: Icons.refresh,
        title: 'Reload library',
        subtitle: 'Fetch channels, movies and series again',
        onTap: active == null ? null : () => s.activate(active),
      ),
      ActionRow(
        icon: Icons.view_timeline_outlined,
        title: 'Reload TV guide',
        subtitle: s.hasGuideSource ? 'Download the programme guide again' : 'This source has no guide',
        onTap: s.hasGuideSource
            ? () {
                s.loadGuide(force: true);
                toast(context, 'Reloading the guide…');
              }
            : null,
      ),
      const SettingsHeader('Saved sources'),
      if (s.sources.isEmpty)
        ListTile(title: Text('No saved sources', style: TextStyle(color: LayoutPalette.of(context).muted))),
      for (final src in s.sources)
        ListTile(
          leading: Icon(
            active?.name == src.name ? Icons.radio_button_checked : Icons.radio_button_off,
            color: active?.name == src.name ? LayoutPalette.of(context).accent : null,
          ),
          title: Text(src.name),
          subtitle: Text(src.type.name.toUpperCase()),
          onTap: active?.name == src.name ? null : () => s.activate(src),
          trailing: IconButton(
            tooltip: 'Remove',
            icon: const Icon(Icons.delete_outline),
            onPressed: () async {
              if (await confirmDialog(context,
                  title: 'Remove "${src.name}"?',
                  body: 'The saved login is deleted from this device.',
                  confirm: 'Remove')) {
                s.removeSource(src);
              }
            },
          ),
        ),
      ActionRow(
        icon: Icons.public,
        title: 'Add free public channels',
        subtitle: 'Browse public lists by category, country or language and add as many as you like',
        onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const FreePlaylistsScreen())),
      ),
      ActionRow(
        icon: Icons.add,
        title: 'Add another source',
        subtitle: 'Opens the connect screen; your saved sources stay',
        onTap: s.signOut,
      ),
    ]);
  }
}

// ---------------------------------------------------------------------------------------

String _langLabel(String v) => const {
      '': 'Automatic',
      'en,eng': 'English',
      'es,spa': 'Spanish',
      'fr,fre,fra': 'French',
      'de,ger,deu': 'German',
      'pt,por': 'Portuguese',
      'it,ita': 'Italian',
      'nl,dut,nld': 'Dutch',
      'pl,pol': 'Polish',
      'tr,tur': 'Turkish',
      'ru,rus': 'Russian',
      'ar,ara': 'Arabic',
      'hi,hin': 'Hindi',
    }[v] ??
    v;

final _languages = [for (final k in const [
      '', 'en,eng', 'es,spa', 'fr,fre,fra', 'de,ger,deu', 'pt,por', 'it,ita', 'nl,dut,nld',
      'pl,pol', 'tr,tur', 'ru,rus', 'ar,ara', 'hi,hin',
    ]) (k, _langLabel(k))];

class PlaybackPage extends StatelessWidget {
  const PlaybackPage({super.key});

  @override
  Widget build(BuildContext context) {
    final st = context.watch<SettingsState>();
    return ListView(children: [
      const SettingsHeader('Watching'),
      SwitchRow(
        icon: Icons.history,
        title: 'Resume automatically',
        subtitle: 'Play continues where you stopped. When off, you choose between starting over and resuming.',
        value: st.autoResume,
        onChanged: (v) => st.set('autoResume', v),
      ),
      SwitchRow(
        icon: Icons.skip_next_outlined,
        title: 'Play the next episode',
        subtitle: 'When an episode ends, the next one starts after a 10 second countdown you can cancel',
        value: st.autoplayNext,
        onChanged: (v) => st.set('autoplayNext', v),
      ),
      ChoiceRow<String>(
        icon: Icons.aspect_ratio,
        title: 'Picture shape',
        subtitle: 'How video fills the screen. The player button changes it for the video you are watching.',
        value: st.aspect,
        options: const [('auto', 'Auto'), ('16:9', '16:9'), ('4:3', '4:3'), ('fill', 'Fill the screen'), ('stretch', 'Stretch')],
        onChanged: (v) => st.set('aspect', v),
      ),
      ChoiceRow<double>(
        icon: Icons.speed,
        title: 'Default movie speed',
        value: st.speed,
        options: const [(0.5, '0.5×'), (0.75, '0.75×'), (1.0, '1×'), (1.25, '1.25×'), (1.5, '1.5×'), (2.0, '2×')],
        onChanged: (v) => st.set('speed', v),
      ),
      const SettingsHeader('Controls'),
      ChoiceRow<int>(
        icon: Icons.fast_forward,
        title: 'Seek step',
        subtitle: 'Left / Right arrows and the skip buttons',
        value: st.seekSecs,
        options: const [(5, '5 seconds'), (10, '10 seconds'), (30, '30 seconds')],
        onChanged: (v) => st.set('seekSecs', v),
      ),
      ChoiceRow<int>(
        icon: Icons.skip_next,
        title: 'Skip-ahead length',
        subtitle: 'The "skip ahead" button, handy for intros',
        value: st.skipSecs,
        options: const [(60, '60 seconds'), (90, '90 seconds'), (120, '2 minutes'), (180, '3 minutes')],
        onChanged: (v) => st.set('skipSecs', v),
      ),
      ChoiceRow<int>(
        icon: Icons.visibility_off_outlined,
        title: 'Hide controls after',
        value: st.controlsHideSecs,
        options: const [(3, '3 seconds'), (5, '5 seconds'), (8, '8 seconds'), (15, '15 seconds'), (0, 'Never')],
        onChanged: (v) => st.set('controlsHideSecs', v),
      ),
      if (!kIsWeb) ...[
        const SettingsHeader('Audio & subtitles'),
        ChoiceRow<String>(
          icon: Icons.audiotrack,
          title: 'Preferred audio language',
          subtitle: 'Used when a stream offers several tracks',
          value: st.audioLang,
          options: _languages,
          onChanged: (v) => st.set('audioLang', v),
        ),
        ChoiceRow<String>(
          icon: Icons.translate,
          title: 'Preferred subtitle language',
          value: st.subLang,
          options: _languages,
          onChanged: (v) => st.set('subLang', v),
        ),
        SwitchRow(
          icon: Icons.closed_caption_outlined,
          title: 'Show subtitles automatically',
          value: st.subsOn,
          onChanged: (v) => st.set('subsOn', v),
        ),
        const SettingsHeader('Performance'),
        ChoiceRow<String>(
          icon: Icons.memory,
          title: 'Decoder',
          subtitle: 'Hardware is faster and cooler. Use Software if playback crashes or the picture glitches',
          value: st.decoder,
          options: const [('auto', 'Hardware (recommended)'), ('software', 'Software')],
          onChanged: (v) => st.set('decoder', v),
        ),
        if (defaultTargetPlatform == TargetPlatform.android)
          ChoiceRow<String>(
            icon: Icons.tv,
            title: 'Video output',
            subtitle: 'Hardware surface is smoothest for movies on Fire TV and Android TV, but cannot draw embedded subtitles or shaders. '
                'Compatible goes through the GPU. Automatic uses the surface on TVs',
            value: st.videoOutput,
            options: const [('auto', 'Automatic'), ('surface', 'Hardware surface'), ('compat', 'Compatible')],
            onChanged: (v) => st.set('videoOutput', v),
          ),
        ChoiceRow<int>(
          icon: Icons.network_check,
          title: 'Network buffer',
          subtitle: 'Higher means fewer stalls on weak connections but slower channel start',
          value: st.bufferSecs,
          options: const [(5, 'Low'), (20, 'Normal'), (60, 'High')],
          onChanged: (v) => st.set('bufferSecs', v),
        ),
        if (shadersSupported)
          ListTile(
            leading: const Icon(Icons.auto_fix_high),
            title: const Text('Shaders'),
            subtitle: Text('${st.activeShaders.length} enabled · sharpen, vibrance, grain, custom GLSL'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ShaderScreen())),
          ),
      ] else
        const ListTile(
          leading: Icon(Icons.info_outline),
          title: Text('Browser playback'),
          subtitle: Text('Your browser decides the decoder, buffering, languages and shaders. '
              'Use a desktop or mobile app for those options.'),
        ),
    ]);
  }
}

// ---------------------------------------------------------------------------------------

class SubtitlesPage extends StatelessWidget {
  const SubtitlesPage({super.key});

  static const _colors = [0xFFFFFFFF, 0xFFFFEB3B, 0xFF00E5FF, 0xFF76FF03, 0xFFFFA726, 0xFFFF80AB];

  @override
  Widget build(BuildContext context) {
    final st = context.watch<SettingsState>();
    return ListView(children: [
      const SettingsHeader('Preview'),
      Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        height: 110,
        alignment: Alignment.center,
        decoration: BoxDecoration(color: LayoutPalette.of(context).surfaceHi, borderRadius: BorderRadius.circular(12)),
        child: Text(
          'The quick brown fox jumps over the lazy dog',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: st.subSize * 0.6,
            fontWeight: st.subBold ? FontWeight.w700 : FontWeight.w400,
            color: Color(st.subColor),
            backgroundColor: st.subBackground ? const Color(0xAA000000) : null,
          ),
        ),
      ),
      SliderRow(
        icon: Icons.format_size,
        title: 'Size',
        value: st.subSize,
        min: 20,
        max: 64,
        divisions: 22,
        label: (v) => '${v.round()}',
        onChanged: (v) => st.set('subSize', v),
      ),
      SliderRow(
        icon: Icons.vertical_align_bottom,
        title: 'Distance from bottom',
        value: st.subBottom,
        min: 0,
        max: 160,
        divisions: 16,
        label: (v) => '${v.round()} px',
        onChanged: (v) => st.set('subBottom', v),
      ),
      ListTile(
        leading: const Icon(Icons.color_lens_outlined),
        title: const Text('Color'),
        trailing: Row(mainAxisSize: MainAxisSize.min, children: [
          for (final c in _colors)
            Padding(
              padding: const EdgeInsets.only(left: 8),
              child: InkResponse(
                onTap: () => st.set('subColor', c),
                child: CircleAvatar(
                  radius: 14,
                  backgroundColor: Color(c),
                  child: st.subColor == c ? const Icon(Icons.check, size: 16, color: Colors.black) : null,
                ),
              ),
            ),
        ]),
      ),
      SwitchRow(
        icon: Icons.format_bold,
        title: 'Bold',
        value: st.subBold,
        onChanged: (v) => st.set('subBold', v),
      ),
      SwitchRow(
        icon: Icons.crop_square,
        title: 'Background box',
        value: st.subBackground,
        onChanged: (v) => st.set('subBg', v),
      ),
    ]);
  }
}

// ---------------------------------------------------------------------------------------

class AppearancePage extends StatelessWidget {
  const AppearancePage({super.key});

  @override
  Widget build(BuildContext context) {
    final st = context.watch<SettingsState>();
    return ListView(children: [
      const SettingsHeader('Layout'),
      const LayoutPicker(),
      const SettingsHeader('Size'),
      ChoiceRow<double>(
        icon: Icons.text_fields,
        title: 'Text size',
        subtitle: 'Larger text is easier to read from the couch',
        value: st.uiScale,
        options: const [(0.85, 'Small'), (1.0, 'Normal'), (1.15, 'Large'), (1.3, 'Extra large')],
        onChanged: (v) => st.set('uiScale', v),
      ),
      ChoiceRow<double>(
        icon: Icons.grid_view,
        title: 'Poster size',
        subtitle: 'Bigger posters show fewer per row',
        value: st.posterSize,
        options: const [(0.85, 'Compact'), (1.0, 'Normal'), (1.25, 'Large')],
        onChanged: (v) => st.set('posterSize', v),
      ),
      const SettingsHeader('TV'),
      ChoiceRow<String>(
        icon: Icons.tv,
        title: 'TV mode',
        subtitle: 'A fixed-size screen layout, a bold focus outline, safe screen margins and Back-to-Home. '
            '${SettingsState.detectedTv ? 'This device was detected as a TV.' : 'Auto turns on for Android TV, Google TV and Fire TV.'}',
        value: st.tvMode,
        options: const [('auto', 'Auto'), ('on', 'On'), ('off', 'Off')],
        onChanged: (v) => st.set('tvMode', v),
      ),
      ChoiceRow<int>(
        icon: Icons.zoom_out_map,
        title: 'TV zoom',
        subtitle: 'How much fits on the TV screen. Smaller sizes show more; use Larger if text is hard to read from the couch. '
            'Applies in TV mode',
        value: st.tvWidth,
        options: const [(1120, 'Larger'), (1280, 'Standard'), (1440, 'Smaller'), (1600, 'Smallest')],
        onChanged: (v) => st.set('tvWidth', v),
      ),
      const SettingsHeader('Startup'),
      ChoiceRow<int>(
        icon: Icons.home_outlined,
        title: 'Open on',
        subtitle: 'The screen shown when the app starts',
        value: st.startTab,
        options: const [(0, 'Home'), (1, 'Live TV'), (2, 'Guide'), (3, 'Movies'), (4, 'Series'), (5, 'Search')],
        onChanged: (v) => st.set('startTab', v),
      ),
    ]);
  }
}

// ---------------------------------------------------------------------------------------

class LibraryPage extends StatelessWidget {
  const LibraryPage({super.key});

  @override
  Widget build(BuildContext context) {
    final st = context.watch<SettingsState>();
    return ListView(children: [
      const SettingsHeader('Browsing'),
      SwitchRow(
        icon: Icons.visibility_off_outlined,
        title: 'Hide adult categories',
        subtitle: 'Hides categories named adult, XXX or 18+ everywhere. A convenience filter, not a parental lock.',
        value: st.hideAdult,
        onChanged: (v) => st.set('hideAdult', v),
      ),
      SwitchRow(
        icon: Icons.sort_by_alpha,
        title: 'Sort A–Z',
        subtitle: 'Alphabetical channels, movies, series and categories instead of the provider\'s order',
        value: st.sortAz,
        onChanged: (v) => st.set('sortAz', v),
      ),
      const SettingsHeader('TV guide'),
      SwitchRow(
        icon: Icons.schedule,
        title: '24-hour clock',
        subtitle: st.use24h ? 'Times like 18:30' : 'Times like 6:30 PM',
        value: st.use24h,
        onChanged: (v) => st.set('use24h', v),
      ),
    ]);
  }
}

// ---------------------------------------------------------------------------------------

class NetworkPage extends StatelessWidget {
  const NetworkPage({super.key});

  Future<void> _customUa(BuildContext context, SettingsState st) async {
    final c = TextEditingController(text: NetConfig.presets.containsValue(st.userAgent) ? '' : st.userAgent);
    final v = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Custom User-Agent'),
        content: TextField(controller: c, autofocus: true, decoration: const InputDecoration(hintText: 'e.g. MyPlayer/1.0')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, c.text.trim()), child: const Text('Save')),
        ],
      ),
    );
    if (v != null) st.set('userAgent', v);
  }

  Future<void> _tmdbKey(BuildContext context, SettingsState st) async {
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
    if (v != null) st.set('tmdbKey', v);
  }

  Future<void> _test(BuildContext context) async {
    final src = context.read<AppState>().active;
    final uri = src == null ? null : Uri.tryParse(src.url);
    if (uri == null || uri.host.isEmpty) {
      toast(context, 'Add a source first');
      return;
    }
    final report = diagnoseConnection(uri, appHttp);
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Connection test'),
        content: SizedBox(
          width: 520,
          child: FutureBuilder<String>(
            future: report,
            builder: (_, snap) => !snap.hasData
                ? const Row(children: [
                    SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
                    SizedBox(width: 12),
                    Text('Testing…'),
                  ])
                : SelectableText(snap.data!, style: const TextStyle(fontFamily: 'monospace', fontSize: 12)),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: await report));
              if (ctx.mounted) toast(ctx, 'Copied');
            },
            child: const Text('Copy'),
          ),
          FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close')),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final st = context.watch<SettingsState>();
    final ua = st.userAgent;
    final uaChoice = ua.isEmpty ? '' : (NetConfig.presets.entries.where((e) => e.value == ua).map((e) => e.key).firstOrNull ?? 'custom');

    return ListView(children: [
      const SettingsHeader('Requests'),
      ChoiceRow<String>(
        icon: Icons.badge_outlined,
        title: 'User-Agent',
        subtitle: kIsWeb
            ? 'Browsers do not allow changing this.'
            : 'Some providers only answer familiar players. Try VLC if a source refuses to connect.',
        value: uaChoice,
        enabled: !kIsWeb,
        options: [('', 'Default'), for (final k in NetConfig.presets.keys) (k, k), ('custom', ua.isEmpty || uaChoice != 'custom' ? 'Custom…' : 'Custom')],
        onChanged: (v) {
          if (v == 'custom') {
            _customUa(context, st);
          } else {
            st.set('userAgent', v.isEmpty ? '' : NetConfig.presets[v]!);
          }
        },
      ),
      if (ua.isNotEmpty && !kIsWeb)
        ListTile(dense: true, title: Text(ua, style: TextStyle(color: LayoutPalette.of(context).muted, fontSize: 12))),
      ActionRow(
        icon: Icons.network_check,
        title: 'Test connection',
        subtitle: kIsWeb
            ? 'Not available in the browser.'
            : 'Checks DNS, IPv4 and IPv6 and an HTTP request to your provider. No logins are shown.',
        onTap: kIsWeb ? null : () => _test(context),
      ),
      const SettingsHeader('Movie & series details'),
      ListTile(
        leading: const Icon(Icons.movie_filter),
        title: const Text('TMDB API key'),
        subtitle: Text(st.tmdbKey.isEmpty
            ? 'Optional. Adds posters, cast and trailers when your provider has none. Not included in backups.'
            : 'Key saved on this device. Not included in backups.'),
        trailing: st.tmdbKey.isEmpty ? null : IconButton(
          tooltip: 'Remove key',
          icon: const Icon(Icons.close),
          onPressed: () => st.set('tmdbKey', ''),
        ),
        onTap: () => _tmdbKey(context, st),
      ),
      ActionRow(
        icon: Icons.open_in_new,
        title: 'Get a free TMDB key',
        subtitle: 'themoviedb.org > Settings > API',
        onTap: () => launchUrl(Uri.parse('https://www.themoviedb.org/settings/api'), mode: LaunchMode.externalApplication),
      ),
    ]);
  }
}

// ---------------------------------------------------------------------------------------

class DataPage extends StatelessWidget {
  const DataPage({super.key});

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final st = context.read<SettingsState>();

    Future<void> clear(String title, String body, VoidCallback run, String done) async {
      if (await confirmDialog(context, title: title, body: body, confirm: 'Clear')) {
        run();
        if (context.mounted) toast(context, done);
      }
    }

    return ListView(children: [
      const SettingsHeader('Backup'),
      ActionRow(
        icon: Icons.upload,
        title: 'Copy backup to clipboard',
        subtitle: 'Sources (without passwords), settings, My List and resume positions. API keys are never included.',
        onTap: () async {
          final data = jsonEncode({'app': s.exportData(), 'settings': st.toMap()});
          await Clipboard.setData(ClipboardData(text: data));
          if (context.mounted) toast(context, 'Backup copied');
        },
      ),
      ActionRow(
        icon: Icons.download,
        title: 'Restore backup from clipboard',
        subtitle: 'Merges into what you have now',
        onTap: () async {
          try {
            final text = (await Clipboard.getData(Clipboard.kTextPlain))?.text ?? '';
            final m = jsonDecode(text) as Map<String, dynamic>;
            s.importData(m['app'] as Map<String, dynamic>);
            st.applyMap(m['settings'] as Map<String, dynamic>);
            st.applyShaderMap(m['settings'] as Map<String, dynamic>);
            if (context.mounted) toast(context, 'Backup restored');
          } catch (_) {
            if (context.mounted) toast(context, 'The clipboard does not hold a valid backup');
          }
        },
      ),
      const SettingsHeader('History'),
      ActionRow(
        icon: Icons.history_toggle_off,
        title: 'Clear "continue watching"',
        subtitle: '${s.recents.length} items',
        onTap: s.recents.isEmpty
            ? null
            : () => clear('Clear continue watching?', 'The recently watched list is emptied. Resume positions stay.', s.clearRecents, 'Cleared'),
      ),
      ActionRow(
        icon: Icons.restart_alt,
        title: 'Forget resume positions',
        subtitle: '${s.positions.length} saved',
        onTap: s.positions.isEmpty
            ? null
            : () => clear('Forget resume positions?', 'Movies and episodes will start from the beginning.', s.clearPositions, 'Cleared'),
      ),
      ActionRow(
        icon: Icons.favorite_border,
        title: 'Clear My List',
        subtitle: '${s.favorites.length} items',
        onTap: s.favorites.isEmpty
            ? null
            : () => clear('Clear My List?', 'All favourites are removed.', s.clearFavorites, 'Cleared'),
      ),
      if (!kIsWeb)
        ActionRow(
          icon: Icons.image_not_supported_outlined,
          title: 'Clear image cache',
          subtitle: 'Posters and logos are downloaded again when needed',
          onTap: () async {
            await DefaultCacheManager().emptyCache();
            if (context.mounted) toast(context, 'Image cache cleared');
          },
        ),
      const SettingsHeader('Reset'),
      ActionRow(
        icon: Icons.settings_backup_restore,
        title: 'Reset all settings',
        subtitle: 'Back to defaults. Sources, My List and history are kept.',
        destructive: true,
        onTap: () async {
          if (await confirmDialog(context,
              title: 'Reset all settings?',
              body: 'Every option on these pages returns to its default.',
              confirm: 'Reset')) {
            st.resetAll();
            if (context.mounted) toast(context, 'Settings reset');
          }
        },
      ),
    ]);
  }
}

// ---------------------------------------------------------------------------------------

class AboutPage extends StatefulWidget {
  const AboutPage({super.key});

  @override
  State<AboutPage> createState() => _AboutPageState();
}

class _AboutPageState extends State<AboutPage> {
  late final Future<PackageInfo> _info = PackageInfo.fromPlatform();
  bool _checking = false;

  Future<void> _check(String current) async {
    setState(() => _checking = true);
    try {
      final u = await checkForUpdate(current);
      if (!mounted) return;
      if (u.newer) {
        final go = await confirmDialog(context,
            title: 'Version ${u.latest} is available',
            body: 'You have $current. Open the download page?',
            confirm: 'Open');
        if (go) launchUrl(Uri.parse(u.url), mode: LaunchMode.externalApplication);
      } else {
        toast(context, 'You are up to date ($current)');
      }
    } catch (e) {
      if (mounted) toast(context, 'Could not check: ${e.toString().replaceFirst('Exception: ', '')}');
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  void _showPlaybackLog(BuildContext context) {
    final log = CrashGuard.lastLog();
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Playback log'),
        content: SizedBox(
          width: 640,
          child: SingleChildScrollView(
            child: SelectableText(
              log.trim().isEmpty ? 'Nothing has been played yet.' : log,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 11, height: 1.35),
            ),
          ),
        ),
        actions: [
          if (log.trim().isNotEmpty)
            TextButton(
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: log));
                if (ctx.mounted) toast(ctx, 'Copied');
              },
              child: const Text('Copy'),
            ),
          FilledButton(autofocus: true, onPressed: () => Navigator.pop(ctx), child: const Text('Close')),
        ],
      ),
    );
  }

  String _diagnostics(PackageInfo i) {
    final app = context.read<AppState>();
    final st = context.read<SettingsState>();
    final lib = app.catalog;
    final settings = st.toMap()..remove('shaderCustom');
    return [
      'StreamBoss ${appVersion(i.version)} (build ${i.buildNumber})',
      'Platform: ${kIsWeb ? 'web' : defaultTargetPlatform.name}',
      'Source: ${app.active?.type.name ?? 'none'}${app.usingXtreamApi ? ' (Xtream API)' : ''}',
      'Library: ${lib.live.length} channels, ${lib.movies.length} movies, ${lib.series.length} series',
      'Guide: ${app.hasGuideSource ? 'available' : 'none'}${app.guideError != null ? ' (error: ${app.guideError})' : ''}',
      'Settings: ${jsonEncode(settings)}',
    ].join('\n');
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<PackageInfo>(
      future: _info,
      builder: (context, snap) {
        final i = snap.data;
        final version = i == null ? '…' : appVersion(i.version);
        return ListView(children: [
          const SettingsHeader('StreamBoss'),
          InfoRow('Version', i == null ? '…' : '$version (build ${i.buildNumber})'),
          ActionRow(
            icon: _checking ? Icons.hourglass_top : Icons.system_update_alt,
            title: 'Check for updates',
            subtitle: 'Looks for a newer release on GitHub',
            onTap: (_checking || i == null) ? null : () => _check(version),
          ),
          ActionRow(
            icon: Icons.new_releases_outlined,
            title: 'Release notes & downloads',
            onTap: () => launchUrl(Uri.parse(kReleasesUrl), mode: LaunchMode.externalApplication),
          ),
          ActionRow(
            icon: Icons.auto_awesome_outlined,
            title: 'Run setup again',
            subtitle: 'The first-run steps: screen, look and playback defaults',
            onTap: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (ctx) => OnboardingScreen(rerun: true, onDone: () => Navigator.of(ctx).pop()),
            )),
          ),
          const SettingsHeader('Support'),
          ActionRow(
            icon: Icons.bug_report_outlined,
            title: 'Report a problem',
            subtitle: 'Opens GitHub issues. Tip: copy diagnostics first and paste them in.',
            onTap: () => launchUrl(Uri.parse(kIssuesUrl), mode: LaunchMode.externalApplication),
          ),
          if (!kIsWeb)
            ActionRow(
              icon: Icons.receipt_long_outlined,
              title: 'Playback log',
              subtitle: 'What the player did last time, to find out why a video would not play',
              onTap: () => _showPlaybackLog(context),
            ),
          ActionRow(
            icon: Icons.content_copy,
            title: 'Copy diagnostics',
            subtitle: 'Version, platform and settings. No logins, addresses or keys.',
            onTap: i == null
                ? null
                : () async {
                    await Clipboard.setData(ClipboardData(text: _diagnostics(i)));
                    if (context.mounted) toast(context, 'Diagnostics copied');
                  },
          ),
          ActionRow(
            icon: Icons.description_outlined,
            title: 'Open-source licenses',
            onTap: () => showLicensePage(
              context: context,
              applicationName: 'StreamBoss',
              applicationVersion: version,
            ),
          ),
          const ListTile(
            leading: Icon(Icons.info_outline),
            title: Text('StreamBoss is a player only'),
            subtitle: Text('No content is included. Use services you are licensed to watch.'),
          ),
        ]);
      },
    );
  }
}
