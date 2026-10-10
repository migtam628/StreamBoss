import 'dart:math' as math;
import 'dart:ui' show PlatformDispatcher;
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:provider/provider.dart';
import 'models/media.dart';
import 'screens/onboarding_screen.dart';
import 'screens/profile_picker_screen.dart';
import 'screens/setup_screen.dart';
import 'services/crash_guard.dart';
import 'services/perf_log.dart';
import 'services/provider_url.dart' show redactUrls;
import 'services/device.dart';
import 'screens/shell.dart';
import 'state/app_state.dart';
import 'services/app_icon.dart';
import 'state/profiles_state.dart';
import 'state/settings_state.dart';
import 'theme.dart';
import 'services/time_format.dart';
import 'services/mini_player.dart';
import 'widgets/live_preview.dart';
import 'widgets/mini_player_overlay.dart';
import 'widgets/screensaver.dart';
import 'widgets/tv.dart';

Future<void> main() async {
  PerfLog.start();
  WidgetsFlutterBinding.ensureInitialized();
  // Keep fewer decoded pictures in memory than Flutter's default (100 MB); fast scrolling through a
  // poster wall on a small TV stick is otherwise enough to get the app closed by the system.
  PaintingBinding.instance.imageCache
    ..maximumSize = 300
    ..maximumSizeBytes = 48 << 20;
  // Anything that goes wrong in Dart code lands in the playback log (Settings > About) instead of
  // vanishing, and one failed task never takes the rest of the app with it.
  FlutterError.onError = (d) {
    FlutterError.presentError(d);
    CrashGuard.log('flutter error ${redactUrls(d.exceptionAsString())}');
  };
  PlatformDispatcher.instance.onError = (e, st) {
    CrashGuard.log('unhandled ${redactUrls('$e')}');
    return true;
  };
  MediaKit.ensureInitialized();
  LivePreview.ready = true;
  await CrashGuard.init();
  await DeviceInfo.init();
  SettingsState.detectedTv = DeviceInfo.isTv;
  final settings = SettingsState();
  await settings.init();
  final profiles = ProfilesState();
  await profiles.init();
  settings.bindProfiles(profiles);
  final state = AppState();
  state.bindSettings(settings);
  state.bindProfiles(profiles);
  PerfLog.mark('settings ready');
  await state.init(waitForLibrary: false);
  PerfLog.mark('state ready');
  // Someone who already has a provider has been through setup, whichever version they came from.
  if (state.sources.isNotEmpty && !settings.onboarded) settings.set('onboarded', true);
  AppIconService.restore(AppIcon.fromKey(settings.appIcon));
  WidgetsBinding.instance.addPostFrameCallback((_) => PerfLog.mark('first frame'));
  runApp(MultiProvider(
    providers: [
      ChangeNotifierProvider.value(value: state),
      ChangeNotifierProvider.value(value: settings),
      ChangeNotifierProvider.value(value: profiles),
    ],
    child: const StreamBossApp(),
  ));
}

class StreamBossApp extends StatelessWidget {
  const StreamBossApp({super.key});

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final st = context.watch<SettingsState>();
    final profiles = context.watch<ProfilesState>();
    final scale = st.textScale;
    final tv = st.isTv;
    return MaterialApp(
      navigatorKey: MiniPlayer.navigatorKey,
      title: 'StreamBoss',
      debugShowCheckedModeBanner: false,
      theme: Boss.theme(tv: tv, layout: st.layout, accent: st.accent, background: st.background),
      builder: (context, child) => TvCanvas(
        enabled: tv,
        width: st.tvWidth,
        child: TvScope(
          tv: tv,
          child: MediaQuery(
            data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),
            child: IdleScreensaver(
              after: Duration(minutes: st.screensaverMinutes),
              view: (_) => ScreensaverView(
                images: screensaverImages(s),
                clock: () => fmtTime(DateTime.now(), use24h: st.use24h),
              ),
              child: Stack(children: [
                Positioned.fill(child: child ?? const SizedBox.shrink()),
                // A saved library is on screen while the provider's current one is fetched.
                if (s.refreshing)
                  const Positioned(top: 0, left: 0, right: 0, child: IgnorePointer(child: LinearProgressIndicator(minHeight: 2))),
                const MiniPlayerOverlay(),
              ]),
            ),
          ),
        ),
      ),
      home: needsOnboarding(st, s)
          ? OnboardingScreen(onDone: () => st.set('onboarded', true))
          : profiles.needsPick
              ? const ProfilePickerScreen()
              : s.active == null || s.error != null || s.loading
              ? const SetupScreen()
              : const Shell(),
    );
  }
}

/// First-run setup shows once, before the connect screen, on a device with no providers saved.
bool needsOnboarding(SettingsState settings, AppState app) =>
    !settings.onboarded && app.sources.isEmpty && app.active == null;

/// Posters and channel logos for the screensaver: a day-stable pick, so it does not reshuffle while it runs.
List<String> screensaverImages(AppState s) {
  final c = s.shown;
  final seed = DateTime.now().day;
  List<String> pick(List<MediaItem> l, int n) {
    final withArt = [for (final i in l) if (i.poster != null && i.poster!.isNotEmpty) i.poster!];
    if (withArt.isEmpty) return const [];
    final out = <String>[];
    final step = math.max(1, withArt.length ~/ n);
    for (var i = seed % step; i < withArt.length && out.length < n; i += step) {
      out.add(withArt[i]);
    }
    return out;
  }

  return [...pick(c.movies, 24), ...pick(c.series, 12), ...pick(c.live, 8)];
}
