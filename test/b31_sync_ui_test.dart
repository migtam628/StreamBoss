import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:streamboss/models/media.dart';
import 'package:streamboss/screens/settings/sync_page.dart';
import 'package:streamboss/screens/setup_screen.dart';
import 'package:streamboss/state/app_state.dart';
import 'package:streamboss/state/settings_state.dart';
import 'package:streamboss/state/sync_state.dart';
import 'package:streamboss/theme.dart';

Future<(AppState, SyncState)> pump(WidgetTester t, Widget home,
    {List<Source> sources = const []}) async {
  SharedPreferences.setMockInitialValues({});
  FlutterSecureStorage.setMockInitialValues({});
  final st = SettingsState();
  await st.init();
  final app = AppState()..bindSettings(st);
  app.sources = sources;
  final sync = SyncState(secure: const FlutterSecureStorage());
  await sync.init();
  t.view.physicalSize = const Size(1000, 1600);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  await t.pumpWidget(MultiProvider(
    providers: [
      ChangeNotifierProvider<AppState>.value(value: app),
      ChangeNotifierProvider<SettingsState>.value(value: st),
      ChangeNotifierProvider<SyncState>.value(value: sync),
    ],
    child: MaterialApp(theme: Boss.theme(), home: home),
  ));
  await t.pumpAndSettle();
  return (app, sync);
}

void main() {
  testWidgets('the setup screen of a new device offers the sync account',
      (t) async {
    await pump(t, const SetupScreen());
    expect(find.text('Use my sync account'), findsOneWidget);
    await t.tap(find.text('Use my sync account'));
    await t.pumpAndSettle();
    final dialog = find.byType(AlertDialog);
    expect(find.descendant(of: dialog, matching: find.text('Sign in')),
        findsWidgets);
    expect(find.descendant(of: dialog, matching: find.text('Server')),
        findsOneWidget);
    expect(find.descendant(of: dialog, matching: find.text('E-mail')),
        findsOneWidget);
    expect(find.descendant(of: dialog, matching: find.text('Password')),
        findsOneWidget);
  });

  testWidgets(
      'a source that arrived without its password asks for it, and keeps it on this device',
      (t) async {
    const src = Source(
        name: 'Panel',
        type: SourceType.xtream,
        url: 'http://panel',
        username: 'u');
    final (app, _) = await pump(t, const SetupScreen(), sources: [src]);
    expect(app.sourceNeedsPassword(src), isTrue);
    expect(find.text('password needed on this device, tap to enter it'),
        findsOneWidget);
    await t.tap(find.text('Panel'));
    await t.pumpAndSettle();
    expect(find.text('Password for "Panel"'), findsOneWidget);
    expect(find.textContaining('Passwords are not synced'), findsOneWidget);
  });

  testWidgets(
      'the Sync page says what it is for and offers sign in or a new account',
      (t) async {
    await pump(t, const Scaffold(body: SyncPage()));
    expect(find.textContaining('server of your own'), findsOneWidget);
    expect(find.text('Sign in'), findsOneWidget);
    expect(find.text('Create an account'), findsOneWidget);
    expect(find.text('Sync now'), findsNothing);
    expect(find.textContaining('Not synced: passwords'), findsOneWidget);
  });

  test('a source with a login in its playlist link needs it back, and gets it',
      () {
    final app = AppState();
    const blank = Source(
        name: 'Link',
        type: SourceType.m3u,
        url: 'http://h/get.php?username=u&password=&type=m3u_plus');
    expect(app.sourceNeedsPassword(blank), isTrue);
    const fine =
        Source(name: 'Link', type: SourceType.m3u, url: 'http://h/list.m3u');
    expect(app.sourceNeedsPassword(fine), isFalse);
    expect(
        app.sourceNeedsPassword(const Source(name: 'D', type: SourceType.demo)),
        isFalse);
    expect(
        app.sourceNeedsPassword(const Source(
            name: 'X',
            type: SourceType.xtream,
            url: 'http://x',
            username: 'u',
            password: 'p')),
        isFalse);
  });
}
