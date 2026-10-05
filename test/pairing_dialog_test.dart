import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:streamboss/models/media.dart';
import 'package:streamboss/screens/pairing_dialog.dart';
import 'package:streamboss/screens/setup_screen.dart';
import 'package:streamboss/services/pairing.dart';
import 'package:streamboss/state/app_state.dart';
import 'package:streamboss/state/settings_state.dart';
import 'package:streamboss/theme.dart';

class FakeSession implements PairingSession {
  final _c = StreamController<Source>.broadcast();
  bool closed = false;
  @override
  String get url => 'http://192.168.1.20:41234';
  @override
  String get pin => '4821';
  @override
  Stream<Source> get sources => _c.stream;
  void send(Source s) => _c.add(s);
  @override
  Future<void> close() async {
    closed = true;
    await _c.close();
  }
}

Future<void> pumpOpener(WidgetTester t, FakeSession? fake, void Function(Source?) onResult) async {
  await t.pumpWidget(MaterialApp(
    theme: Boss.theme(),
    home: Builder(
      builder: (ctx) => Scaffold(
        body: Center(
          child: TextButton(
            onPressed: () async => onResult(await showPairingDialog(ctx, start: () async => fake)),
            child: const Text('open'),
          ),
        ),
      ),
    ),
  ));
  await t.tap(find.text('open'));
  await t.pumpAndSettle();
}

void main() {
  testWidgets('shows the address and PIN, then returns the Source the phone sends', (t) async {
    final fake = FakeSession();
    Source? got;
    await pumpOpener(t, fake, (s) => got = s);
    expect(find.text('Set up from your phone'), findsOneWidget);
    expect(find.textContaining('http://192.168.1.20:41234', findRichText: true), findsOneWidget);
    expect(find.textContaining('4821', findRichText: true), findsOneWidget);

    fake.send(const Source(name: 'Home', type: SourceType.xtream, url: 'http://h', username: 'u', password: 'p'));
    await t.pumpAndSettle();
    expect(got?.name, 'Home');
    expect(find.text('Set up from your phone'), findsNothing);
    expect(fake.closed, true, reason: 'the server stops once the login arrives');
  });

  testWidgets('Cancel closes the session and returns null', (t) async {
    final fake = FakeSession();
    Source? got = const Source(name: 'x', type: SourceType.demo);
    await pumpOpener(t, fake, (s) => got = s);
    await t.tap(find.text('Cancel'));
    await t.pumpAndSettle();
    expect(got, isNull);
    expect(fake.closed, true);
  });

  testWidgets('explains when the device has no network address', (t) async {
    await pumpOpener(t, null, (_) {});
    expect(find.textContaining('no home-network address'), findsOneWidget);
  });

  testWidgets('the setup screen offers phone setup on devices that can host it', (t) async {
    SharedPreferences.setMockInitialValues({});
    final st = SettingsState();
    await st.init();
    t.view.physicalSize = const Size(1000, 1400);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider<AppState>(create: (_) => AppState()),
        ChangeNotifierProvider<SettingsState>.value(value: st),
      ],
      child: MaterialApp(theme: Boss.theme(), home: const SetupScreen()),
    ));
    expect(find.text('Set up from your phone'), pairingSupported ? findsOneWidget : findsNothing);
  });
}
