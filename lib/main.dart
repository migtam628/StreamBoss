import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:provider/provider.dart';
import 'screens/setup_screen.dart';
import 'services/crash_guard.dart';
import 'services/device.dart';
import 'screens/shell.dart';
import 'state/app_state.dart';
import 'state/settings_state.dart';
import 'theme.dart';
import 'widgets/tv.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  await CrashGuard.init();
  await DeviceInfo.init();
  SettingsState.detectedTv = DeviceInfo.isTv;
  final settings = SettingsState();
  await settings.init();
  final state = AppState();
  state.bindSettings(settings);
  await state.init();
  runApp(MultiProvider(
    providers: [
      ChangeNotifierProvider.value(value: state),
      ChangeNotifierProvider.value(value: settings),
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
    final scale = st.textScale;
    final tv = st.isTv;
    return MaterialApp(
      title: 'StreamBoss',
      debugShowCheckedModeBanner: false,
      theme: Boss.theme(tv: tv),
      builder: (context, child) => TvScope(
        tv: tv,
        child: MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),
          child: child ?? const SizedBox.shrink(),
        ),
      ),
      home: s.active == null || s.error != null || s.loading
          ? const SetupScreen()
          : const Shell(),
    );
  }
}
