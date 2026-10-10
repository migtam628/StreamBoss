import 'dart:convert';
import 'package:flutter/foundation.dart' show defaultTargetPlatform, kIsWeb;
import 'package:flutter/material.dart';
import '../../services/app_icon.dart';
import '../../services/catalog_cache.dart';
import '../../services/perf_log.dart';
import '../../services/boot_launch.dart';
import '../../widgets/screensaver.dart';
import '../../layouts/common.dart';
import '../../layouts/ui_layout.dart';
import '../../layouts/layout_picker.dart';
import '../../layouts/theme_picker.dart';
import '../collections_screen.dart';
import '../edited_channels_screen.dart';
import '../free_playlists_screen.dart';
import '../onboarding_screen.dart';
import 'package:flutter/services.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../app_info.dart';
import '../../models/media.dart';
import '../../services/cast_service.dart';
import '../../services/countries.dart';
import '../../services/crash_guard.dart';
import '../../services/library_view.dart' show isKidsCategory;
import '../../services/http_client.dart';
import '../../services/mpv_props.dart';
import '../../services/net_config.dart';
import '../../services/update_check.dart';
import '../../widgets/update_dialog.dart';
import '../../models/profile.dart';
import '../../state/app_state.dart';
import '../../state/profiles_state.dart';
import '../../widgets/pin_dialog.dart';
import '../profile_picker_screen.dart';
import '../../state/settings_state.dart';
import '../shader_screen.dart';
import 'settings_widgets.dart';
import '../../widgets/tv_text_field.dart';

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
  SettingsSection('Profiles & PIN', 'Who is watching, Kids profiles, PIN lock', Icons.family_restroom, (_) => const ProfilesPage()),
  SettingsSection('Network & metadata', 'User-Agent, TMDB', Icons.public, (_) => const NetworkPage()),
  SettingsSection('Data & backup', 'Backup, history, reset', Icons.storage_outlined, (_) => const DataPage()),
  SettingsSection('About', 'Version, updates, support', Icons.info_outline, (_) => const AboutPage()),
];

// ---------------------------------------------------------------------------------------

/// What is saved on this device so the next start is quick, and how to clear it.
class _SavedLibraryRow extends StatefulWidget {
  const _SavedLibraryRow();

  @override
  State<_SavedLibraryRow> createState() => _SavedLibraryRowState();
}

class _SavedLibraryRowState extends State<_SavedLibraryRow> {
  late Future<int> _size = CatalogCache.size();

  String _ago(DateTime t) {
    final m = DateTime.now().difference(t).inMinutes;
    if (m < 1) return 'just now';
    if (m < 60) return '$m min ago';
    if (m < 48 * 60) return '${m ~/ 60} h ago';
    return '${m ~/ (24 * 60)} days ago';
  }

  @override
  Widget build(BuildContext context) {
    if (!CatalogCache.supported) return const SizedBox.shrink();
    final s = context.watch<AppState>();
    return FutureBuilder<int>(
      future: _size,
      builder: (context, snap) {
        final mb = (snap.data ?? 0) / 1048576;
        final status = s.refreshing
            ? 'Showing the copy saved ${s.libraryFrom == null ? 'earlier' : _ago(s.libraryFrom!)}; updating it now.'
            : s.refreshError != null
                ? 'Could not update the saved copy: ${s.refreshError}'
                : 'The library is saved on this device so the next start is quick.';
        return ActionRow(
          icon: Icons.bolt_outlined,
          title: 'Clear saved library',
          subtitle: '$status ${mb < 0.05 ? '' : '(${mb.toStringAsFixed(1)} MB) '}The next start loads from the provider again.',
          onTap: () async {
            await CatalogCache.clear();
            if (!mounted) return;
            setState(() => _size = CatalogCache.size());
            // ignore: use_build_context_synchronously
            toast(context, 'Saved library cleared');
          },
        );
      },
    );
  }
}

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
        subtitle: Text('$type${s.sourceCount > 1 ? ' + ${s.sourceCount - 1} more' : ''}\n${lib.live.length} channels · ${lib.movies.length} movies · '
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
      const _SavedLibraryRow(),
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
      const SettingsHeader('Channel check'),
      if (kIsWeb)
        const ListTile(
          leading: Icon(Icons.fact_check_outlined),
          title: Text('Check live channels'),
          subtitle: Text('Needs the app. A browser cannot test other sites\' streams.'),
          enabled: false,
        )
      else if (s.checking)
        ListTile(
          isThreeLine: true,
          leading: const Icon(Icons.fact_check_outlined),
          title: Text('Checking… ${s.checkDone} of ${s.checkTotal}'),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              LinearProgressIndicator(value: s.checkTotal == 0 ? null : s.checkDone / s.checkTotal),
              const SizedBox(height: 6),
              Text('${s.checkDeadSoFar} offline so far'),
            ]),
          ),
          trailing: TextButton(onPressed: s.cancelCheck, child: const Text('Stop')),
        )
      else
        ActionRow(
          icon: Icons.fact_check_outlined,
          title: s.checkedCount == 0 ? 'Check live channels' : 'Check live channels again',
          subtitle: s.checkedCount == 0
              ? 'Tests every channel and flags the ones that do not answer. '
                  '${s.catalog.live.length} channels${s.usingXtreamApi || active?.type == SourceType.xtream ? ', two at a time because logins limit simultaneous streams' : ''}'
              : 'Last check: ${s.checkedCount} channels, ${s.deadKeys.length} offline',
          onTap: s.canCheck ? s.checkLive : null,
        ),
      SwitchRow(
        icon: Icons.visibility_off_outlined,
        title: 'Hide offline channels',
        subtitle: s.deadKeys.isEmpty ? 'Run a check first' : 'Removes the ${s.deadKeys.length} channels that failed the last check',
        value: context.watch<SettingsState>().hideDead,
        onChanged: s.deadKeys.isEmpty ? (_) {} : (v) => context.read<SettingsState>().set('hideDead', v),
      ),
      if (s.checkedCount > 0 && !s.checking)
        ActionRow(
          icon: Icons.restart_alt,
          title: 'Forget check results',
          subtitle: 'Shows every channel again',
          onTap: s.forgetCheck,
        ),
      const SettingsHeader('Saved sources'),
      if (s.sources.isEmpty)
        ListTile(title: Text('No saved sources', style: TextStyle(color: LayoutPalette.of(context).muted))),
      for (final src in s.sources)
        ListTile(
          isThreeLine: s.extraErrors.containsKey(src.name),
          leading: Icon(
            active?.name == src.name ? Icons.radio_button_checked : Icons.radio_button_off,
            color: active?.name == src.name ? LayoutPalette.of(context).accent : null,
          ),
          title: Text(src.name),
          subtitle: Text([
            src.type.name.toUpperCase(),
            if (active?.name == src.name) 'main source' else if (s.extraSources.contains(src.name)) 'also in the library',
            if (s.extraErrors[src.name] != null) '\nCould not load: ${s.extraErrors[src.name]}',
          ].join(' · ').replaceAll(' · \n', '\n')),
          onTap: active?.name == src.name ? null : () => s.activate(src),
          trailing: Row(mainAxisSize: MainAxisSize.min, children: [
            if (active != null && active.name != src.name)
              Tooltip(
                message: 'Also show this source in the library',
                child: Switch(
                  value: s.extraSources.contains(src.name),
                  onChanged: (v) => s.setExtraSource(src.name, v),
                ),
              ),
            IconButton(
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
          ]),
        ),
      if (s.sources.length > 1)
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
          child: Text(
            'Tap a source to make it the main one. The switch on the others adds them to the same library, '
            'so channels, movies and guides from all of them are listed together. My List and history stay with the main source.',
            style: TextStyle(color: LayoutPalette.of(context).muted, fontSize: 13, height: 1.4),
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
      SwitchRow(
        icon: Icons.skip_next_outlined,
        title: 'Next episode at the credits',
        subtitle: 'When a file marks its credits, offer the next episode as they start instead of when the file ends. '
            'Needs "Play the next episode" above.',
        value: st.creditsNext,
        onChanged: (v) => st.set('creditsNext', v),
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
      const SettingsHeader('Colors'),
      const ThemePicker(),
      if (AppIconService.supported) ...[
        const SettingsHeader('App icon'),
        const AppIconPicker(),
      ],
      SwitchRow(
        icon: Icons.live_tv,
        title: 'Live pictures',
        subtitle: 'Cable Box and Mosaic play their channels right on the home screen. '
            'Turn this off if your device stutters.',
        value: st.livePreview,
        onChanged: (v) => st.set('livePreview', v),
      ),
      ChoiceRow<String>(
        icon: Icons.nightlight_outlined,
        title: 'Screensaver',
        subtitle: 'Drifting posters when nothing has been pressed for a while and nothing is playing. '
            'Auto is 10 minutes on a TV and off elsewhere.',
        value: st.screensaver,
        options: const [('auto', 'Auto'), ('off', 'Off'), ('2', '2 min'), ('5', '5 min'), ('10', '10 min'), ('20', '20 min'), ('30', '30 min')],
        onChanged: (v) => st.set('screensaver', v),
      ),
      ActionRow(
        icon: Icons.slideshow_outlined,
        title: 'Preview the screensaver',
        subtitle: 'Press any key or touch the screen to come back',
        onTap: () => Screensaver.preview.value++,
      ),
      ChoiceRow<String>(
        icon: Icons.bedtime_outlined,
        title: 'Playground bedtime',
        subtitle: 'The Playground layout shows "All done for today" from this time until 5 in the morning.',
        value: st.bedtime,
        options: const [('off', 'Off'), ('18:00', '6 PM'), ('19:00', '7 PM'), ('20:00', '8 PM'), ('21:00', '9 PM')],
        onChanged: (v) => st.set('bedtime', v),
      ),
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
        subtitle: 'The screen shown when the app starts. Where I left off reopens the last screen, and the last live channel if you were watching one',
        value: st.startTab,
        options: const [(-1, 'Where I left off'), (0, 'Home'), (1, 'Live TV'), (2, 'Guide'), (3, 'Movies'), (4, 'Series'), (7, 'Anime'), (5, 'Search')],
        onChanged: (v) => st.set('startTab', v),
      ),
      if (BootLaunch.supported)
        SwitchRow(
          icon: Icons.power_settings_new,
          title: 'Open when the device starts',
          subtitle: 'Opens StreamBoss when the Fire TV or Android TV is switched on or restarted. With Open on set to '
              'Where I left off it goes straight back to the channel you were watching.',
          value: st.startOnBoot,
          onChanged: (v) async {
            st.set('startOnBoot', v);
            if (v && !await BootLaunch.allowed() && context.mounted) {
              final open = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Text('One more step'),
                  content: const Text('This version of Android only lets an app open itself at start-up if it may '
                      '"Display over other apps". Turn that on for StreamBoss on the next screen.'),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Not now')),
                    FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Open settings')),
                  ],
                ),
              );
              if (open == true && !await BootLaunch.openPermissionSettings() && context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                    content: Text('This device has no such screen. Look for StreamBoss under Apps > Special access.')));
              }
            }
          },
        ),
      ChoiceRow<String>(
        icon: Icons.auto_awesome_outlined,
        title: 'Anime page',
        subtitle: 'Auto shows it in the menus when your library has anime. On always shows it, Off hides it.',
        value: st.animePage,
        options: const [('auto', 'Auto'), ('on', 'Always'), ('off', 'Hidden')],
        onChanged: (v) => st.set('animePage', v),
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
        icon: Icons.merge_type,
        title: 'Merge duplicate channels',
        subtitle: 'Shows one entry when a channel is listed several times (HD, SD, a backup). '
            'The best copy plays, and the others take over if it fails.',
        value: st.mergeDuplicates,
        onChanged: (v) => st.set('mergeDuplicates', v),
      ),
      SwitchRow(
        icon: Icons.sort_by_alpha,
        title: 'Sort A–Z',
        subtitle: 'Alphabetical channels, movies, series and categories instead of the provider\'s order',
        value: st.sortAz,
        onChanged: (v) => st.set('sortAz', v),
      ),
      ActionRow(
        icon: Icons.edit_note,
        title: 'Edited channels',
        subtitle: 'Channels you renamed, hid or pinned to the top. Undo any of them here.',
        onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const EditedChannelsScreen())),
      ),
      ActionRow(
        icon: Icons.collections_bookmark_outlined,
        title: 'Collections',
        subtitle: 'Lists you name, like "Friday movie night". Add to one from a movie or series page.',
        onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const CollectionsScreen())),
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

class ProfilesPage extends StatelessWidget {
  const ProfilesPage({super.key});

  @override
  Widget build(BuildContext context) {
    final ps = Provider.of<ProfilesState?>(context);
    if (ps == null) return const SizedBox.shrink();
    final app = context.read<AppState>();
    final p = LayoutPalette.of(context);
    return ListView(children: [
      const SettingsHeader('Profiles'),
      for (final pr in ps.profiles)
        ListTile(
          leading: ProfileAvatar(pr, size: 40),
          title: Text('${pr.name}${pr.id == ps.currentId ? '  ·  in use' : ''}'),
          subtitle: Text([
            if (pr.kids) 'Kids',
            if (pr.locked && ps.hasPin) 'PIN to open',
            if (pr.ownSettings) 'Own settings',
            if (!pr.kids && !(pr.locked && ps.hasPin) && !pr.ownSettings) 'Own My List, history and resume positions',
          ].join(' · ')),
          trailing: const Icon(Icons.more_horiz),
          onTap: () => _editProfile(context, ps, app, pr),
        ),
      ActionRow(
        icon: Icons.person_add_alt_1,
        title: 'Add a profile',
        subtitle: ps.canAdd ? 'Each profile keeps its own My List, history and resume positions' : 'The limit is eight profiles',
        onTap: ps.canAdd ? () => _addProfile(context, ps) : null,
      ),
      if (ps.multiple)
        ActionRow(
          icon: Icons.switch_account_outlined,
          title: "Who's watching?",
          subtitle: 'Switch to another profile',
          onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ProfilePickerScreen())),
        ),
      const SettingsHeader('PIN lock'),
      if (!ps.hasPin)
        ActionRow(
          icon: Icons.lock_outline,
          title: 'Set a PIN',
          subtitle: 'Four digits. Locks Settings while a Kids profile is in use',
          onTap: () async {
            final pin = await askNewPin(context);
            if (pin != null) {
              ps.setPin(pin);
              if (context.mounted) toast(context, 'PIN set');
            }
          },
        )
      else ...[
        ActionRow(
          icon: Icons.password,
          title: 'Change PIN',
          onTap: () async {
            if (!await askPin(context, ps, title: 'Current PIN') || !context.mounted) return;
            final pin = await askNewPin(context, title: 'Choose a new PIN');
            if (pin != null) {
              ps.setPin(pin);
              if (context.mounted) toast(context, 'PIN changed');
            }
          },
        ),
        ActionRow(
          icon: Icons.lock_open,
          title: 'Remove PIN',
          subtitle: 'Kids profiles stay, but nothing is locked any more',
          destructive: true,
          onTap: () async {
            if (!await askPin(context, ps, title: 'Current PIN') || !context.mounted) return;
            ps.clearPin();
            toast(context, 'PIN removed');
          },
        ),
      ],
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        child: Text(
          'With a PIN set: Settings are locked while a Kids profile is in use, leaving a Kids profile asks for the PIN, '
          'and a profile marked "Needs PIN" asks for it too. A Kids profile shows only categories that look made for '
          'children, judged by their names. This is a family lock for a shared screen, not high security.',
          style: TextStyle(color: p.muted, height: 1.4),
        ),
      ),
    ]);
  }
}

Future<String?> _askText(BuildContext context, String title, String initial, {String confirm = 'Save'}) {
  final c = TextEditingController(text: initial);
  return showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: TvTextField(
        controller: c,
        autofocus: true,
        maxLength: 20,
        textCapitalization: TextCapitalization.words,
        onSubmitted: (v) => Navigator.pop(ctx, v.trim()),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(ctx, c.text.trim()), child: Text(confirm)),
      ],
    ),
  );
}

Future<void> _addProfile(BuildContext context, ProfilesState ps) async {
  var kids = false;
  final c = TextEditingController();
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setS) => AlertDialog(
        title: const Text('New profile'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TvTextField(
              controller: c,
              autofocus: true,
              maxLength: 20,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(labelText: 'Name')),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Kids profile'),
            subtitle: const Text('Only child-friendly categories'),
            value: kids,
            onChanged: (v) => setS(() => kids = v),
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Add')),
        ],
      ),
    ),
  );
  if (ok == true) {
    ps.add(c.text, kids: kids);
    if (kids && !ps.hasPin && context.mounted) {
      toast(context, 'Set a PIN below so children cannot leave this profile');
    }
  }
}

Future<void> _editProfile(BuildContext context, ProfilesState ps, AppState app, Profile pr) {
  return showDialog<void>(
    context: context,
    builder: (ctx) => StatefulBuilder(builder: (ctx, setS) {
      final cur = ps.profiles.firstWhere((e) => e.id == pr.id, orElse: () => pr);
      return SimpleDialog(
        title: Text(cur.name),
        children: [
          if (cur.id != ps.currentId)
            SimpleDialogOption(
              onPressed: () async {
                Navigator.pop(ctx);
                await switchProfile(context, ps, cur);
              },
              child: const Text('Use this profile'),
            ),
          SimpleDialogOption(
            onPressed: () async {
              Navigator.pop(ctx);
              final n = await _askText(context, 'Rename profile', cur.name);
              if (n != null && n.isNotEmpty) ps.update(cur.copyWith(name: n));
            },
            child: const Text('Rename'),
          ),
          SwitchListTile(
            title: const Text('Kids profile'),
            subtitle: const Text('Only child-friendly categories'),
            value: cur.kids,
            onChanged: (v) {
              ps.update(cur.copyWith(kids: v));
              setS(() {});
            },
          ),
          SwitchListTile(
            title: const Text('Own settings'),
            subtitle: const Text('Its own layout, text size, languages, subtitles and filters'),
            value: cur.ownSettings,
            onChanged: (v) {
              ps.update(cur.copyWith(ownSettings: v));
              setS(() {});
            },
          ),
          if (ps.hasPin)
            SwitchListTile(
              title: const Text('Needs PIN to open'),
              value: cur.locked,
              onChanged: (v) {
                ps.update(cur.copyWith(locked: v));
                setS(() {});
              },
            ),
          if (ps.profiles.length > 1)
            SimpleDialogOption(
              onPressed: () async {
                Navigator.pop(ctx);
                if (await confirmDialog(context,
                    title: 'Delete "${cur.name}"?',
                    body: 'Its My List, history and resume positions are deleted from this device.',
                    confirm: 'Delete')) {
                  if (ps.remove(cur.id)) await app.forgetProfile(cur.id);
                }
              },
              child: Text('Delete', style: TextStyle(color: Theme.of(ctx).colorScheme.error)),
            ),
        ],
      );
    }),
  );
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
        content: TvTextField(controller: c, autofocus: true, decoration: const InputDecoration(hintText: 'e.g. MyPlayer/1.0')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, c.text.trim()), child: const Text('Save')),
        ],
      ),
    );
    if (v != null) st.set('userAgent', v);
  }

  Future<void> _osLogin(BuildContext context, SettingsState st) async {
    final key = TextEditingController(text: st.osKey);
    final user = TextEditingController(text: st.osUser);
    final pass = TextEditingController(text: st.osPass);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('OpenSubtitles'),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TvTextField(controller: key, autofocus: true, decoration: const InputDecoration(labelText: 'API key')),
            TvTextField(controller: user, decoration: const InputDecoration(labelText: 'Username (needed to download)')),
            TvTextField(controller: pass, obscureText: true, decoration: const InputDecoration(labelText: 'Password')),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Save')),
        ],
      ),
    );
    if (ok == true) {
      st.set('osKey', key.text.trim());
      st.set('osUser', user.text.trim());
      st.set('osPass', pass.text);
    }
  }

  Future<void> _tmdbKey(BuildContext context, SettingsState st) async {
    final c = TextEditingController(text: st.tmdbKey);
    final v = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('TMDB API key (v3)'),
        content: TvTextField(controller: c, autofocus: true),
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
      ListTile(
        leading: const Icon(Icons.subtitles_outlined),
        title: const Text('OpenSubtitles'),
        subtitle: Text(st.osKey.isEmpty
            ? 'Optional. Lets you search for subtitles from the player. Needs your own free API key; '
                'downloading also needs your account. Not included in backups.'
            : 'Saved on this device. Not included in backups.'),
        trailing: st.osKey.isEmpty ? null : IconButton(
          tooltip: 'Remove',
          icon: const Icon(Icons.close),
          onPressed: () {
            st.set('osKey', '');
            st.set('osUser', '');
            st.set('osPass', '');
          },
        ),
        onTap: () => _osLogin(context, st),
      ),
      SwitchRow(
        icon: Icons.image_outlined,
        title: 'Fill in missing posters',
        subtitle: st.tmdbKey.isEmpty
            ? 'Needs the TMDB key above. Looks up a poster for movies and series your provider has none for.'
            : 'Looks up a poster for movies and series your provider has none for, and remembers it.',
        value: st.realPosters,
        onChanged: (v) => st.set('realPosters', v),
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
        await showUpdateDialog(context, u, current);
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
    final countries = groupByCountry(lib);
    // Category names that name no country, to improve the parser. Names only, never addresses.
    final unmatched = [
      for (final c in lib.liveCategories)
        if (countryOf(c.name) == null) c.name
    ];
    final kids = [
      for (final c in [...lib.liveCategories, ...lib.movieCategories, ...lib.seriesCategories])
        if (isKidsCategory(c.name)) c.name
    ];
    return [
      'StreamBoss ${appVersion(i.version)} (build ${i.buildNumber})',
      'Platform: ${kIsWeb ? 'web' : defaultTargetPlatform.name}',
      'Source: ${app.active?.type.name ?? 'none'}${app.usingXtreamApi ? ' (Xtream API)' : ''}',
      'Library: ${lib.live.length} channels, ${lib.movies.length} movies, ${lib.series.length} series',
      'Layout: ${st.layout.name}, TV mode ${st.isTv ? 'on' : 'off'}, video output ${st.videoOutput}, live pictures ${st.livePreview ? 'on' : 'off'}',
      'Cast: ${castSupported ? 'available (experimental)' : 'not on this platform'}',
      'Countries found: ${countries.length}${countries.isEmpty ? '' : ' (${countries.take(8).map((g) => '${g.country.code} ${g.channels.length}').join(', ')})'}',
      'Live categories with no country: ${unmatched.length}${unmatched.isEmpty ? '' : ' (${unmatched.take(12).join(' | ')})'}',
      'Kids categories matched: ${kids.length}${kids.isEmpty ? '' : ' (${kids.take(8).join(' | ')})'}',
      'Guide: ${app.hasGuideSource ? 'available' : 'none'}${app.guideError != null ? ' (error: ${app.guideError})' : ''}',
      'Performance:',
      ...PerfLog.report().map((l) => '  $l'),
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

/// Settings > Appearance > App icon: the four icons as tiles. Tapping one changes the icon of the
/// installed app (see AppIconService for what that means on each system).
class AppIconPicker extends StatefulWidget {
  const AppIconPicker({super.key});

  @override
  State<AppIconPicker> createState() => _AppIconPickerState();
}

class _AppIconPickerState extends State<AppIconPicker> {
  @override
  void initState() {
    super.initState();
    // The system is the truth on Android (an older install, or a change made elsewhere).
    AppIconService.current().then((c) {
      if (!mounted || c == null) return;
      final st = context.read<SettingsState>();
      if (st.appIcon != c.name) st.set('appIcon', c.name);
    });
  }

  Future<void> _pick(AppIcon icon) async {
    final st = context.read<SettingsState>();
    final messenger = ScaffoldMessenger.of(context);
    final ok = await AppIconService.set(icon);
    if (ok) st.set('appIcon', icon.name);
    messenger.showSnackBar(SnackBar(
        content: Text(ok
            ? '${icon.label} icon set. Your launcher can take a few seconds to show it.'
            : 'The icon could not be changed on this device.')));
  }

  @override
  Widget build(BuildContext context) {
    final p = LayoutPalette.of(context);
    final cur = AppIcon.fromKey(context.watch<SettingsState>().appIcon);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      child: Wrap(spacing: 14, runSpacing: 14, children: [
        for (final icon in AppIcon.values)
          FocusSurface(
            radius: 16,
            semanticLabel: '${icon.label} icon${icon == cur ? ', selected' : ''}',
            onTap: () => _pick(icon),
            builder: (_, __) => Container(
              width: 104,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: p.surface,
                border: Border.all(color: icon == cur ? p.accent : Colors.transparent, width: 2),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Image.asset(icon.asset, width: 72, height: 72, filterQuality: FilterQuality.medium),
                const SizedBox(height: 8),
                Row(mainAxisSize: MainAxisSize.min, children: [
                  if (icon == cur) Icon(Icons.check_circle, size: 16, color: p.accent),
                  if (icon == cur) const SizedBox(width: 4),
                  Flexible(child: Text(icon.label, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700))),
                ]),
              ]),
            ),
          ),
      ]),
    );
  }
}
