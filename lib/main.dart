import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:provider/provider.dart';
import 'screens/setup_screen.dart';
import 'screens/shell.dart';
import 'state/app_state.dart';
import 'state/settings_state.dart';
import 'theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
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
    final scale = context.watch<SettingsState>().uiScale;
    return MaterialApp(
      title: 'StreamBoss',
      debugShowCheckedModeBanner: false,
      theme: Boss.theme(),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),
        child: child ?? const SizedBox.shrink(),
      ),
      home: s.active == null || s.error != null || s.loading
          ? const SetupScreen()
          : const Shell(),
    );
  }
}
