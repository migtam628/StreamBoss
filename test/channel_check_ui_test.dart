import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:streamboss/models/media.dart';
import 'package:streamboss/screens/settings_screen.dart';
import 'package:streamboss/state/app_state.dart';
import 'package:streamboss/state/settings_state.dart';
import 'package:streamboss/theme.dart';

void main() {
  testWidgets(
      'Source settings offer the channel check and explain the empty state',
      (t) async {
    SharedPreferences.setMockInitialValues({});
    final st = SettingsState();
    await st.init();
    final app = AppState()..bindSettings(st);
    await app.init();
    app.active =
        const Source(name: 'Free', type: SourceType.m3u, url: 'http://x/y.m3u');
    app.catalog = const Catalog(live: [
      MediaItem(
          id: '1', name: 'One', kind: MediaKind.live, streamUrl: 'http://x/1'),
      MediaItem(
          id: '2', name: 'Two', kind: MediaKind.live, streamUrl: 'http://x/2'),
    ]);
    t.view.physicalSize = const Size(1200, 1400);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider<AppState>.value(value: app),
        ChangeNotifierProvider<SettingsState>.value(value: st),
      ],
      child: MaterialApp(
          theme: Boss.theme(), home: const Scaffold(body: SettingsScreen())),
    ));
    await t.pumpAndSettle();

    expect(find.text('CHANNEL CHECK'), findsOneWidget);
    expect(find.text('Check live channels'), findsOneWidget);
    expect(find.textContaining('2 channels'), findsWidgets);
    expect(find.text('Hide offline channels'), findsOneWidget);
    expect(find.text('Run a check first'), findsOneWidget);
    expect(find.text('Forget check results'), findsNothing);
  });

  test('Live pictures and Hide offline channels default sensibly and are saved',
      () async {
    SharedPreferences.setMockInitialValues({});
    final st = SettingsState();
    await st.init();
    expect(st.livePreview, isTrue);
    expect(st.hideDead, isFalse);
    st.set('livePreview', false);
    st.set('hideDead', true);
    final again = SettingsState();
    await again.init();
    expect(again.livePreview, isFalse);
    expect(again.hideDead, isTrue);
  });
}
