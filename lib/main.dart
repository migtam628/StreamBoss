import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:provider/provider.dart';
import 'models/media.dart';
import 'screens/onboarding_screen.dart';
import 'screens/profile_picker_screen.dart';
import 'screens/setup_screen.dart';
import 'services/crash_guard.dart';
import 'services/device.dart';
import 'screens/shell.dart';
import 'state/app_state.dart';
import 'services/app_icon.dart';
import 'state/profiles_state.dart';
import 'state/settings_state.dart';
import 'theme.dart';
import 'services/time_format.dart';
import 'widgets/live_preview.dart';
import 'widgets/screensaver.dart';
import 'widgets/tv.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
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
  await state.init();
  // Someone who already has a provider has been through setup, whichever version they came from.
  if (state.sources.isNotEmpty && !settings.onboarded) settings.set('onboarded', true);
  AppIconService.restore(AppIcon.fromKey(settings.appIcon));
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
              child: child ?? const SizedBox.shrink(),
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
