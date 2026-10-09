import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:streamboss/screens/profile_picker_screen.dart';
import 'package:streamboss/screens/settings_screen.dart';
import 'package:streamboss/state/app_state.dart';
import 'package:streamboss/state/profiles_state.dart';
import 'package:streamboss/state/settings_state.dart';
import 'package:streamboss/theme.dart';
import 'package:streamboss/widgets/pin_dialog.dart';

late ProfilesState ps;

Future<void> pump(WidgetTester t, Widget home,
    {void Function(ProfilesState)? setup}) async {
  SharedPreferences.setMockInitialValues({});
  final st = SettingsState();
  await st.init();
  ps = ProfilesState();
  await ps.init();
  setup?.call(ps);
  final app = AppState()
    ..bindSettings(st)
    ..bindProfiles(ps);
  t.view.physicalSize = const Size(1200, 900);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  await t.pumpWidget(MultiProvider(
    providers: [
      ChangeNotifierProvider<AppState>.value(value: app),
      ChangeNotifierProvider<SettingsState>.value(value: st),
      ChangeNotifierProvider<ProfilesState>.value(value: ps),
    ],
    child: MaterialApp(theme: Boss.theme(), home: home),
  ));
  await t.pumpAndSettle();
}

Future<void> typePin(WidgetTester t, String pin) async {
  for (final d in pin.split('')) {
    await t.tap(
        find.descendant(of: find.byType(AlertDialog), matching: find.text(d)));
    await t.pump();
  }
  await t.pumpAndSettle();
}

class _Ask extends StatefulWidget {
  const _Ask();
  @override
  State<_Ask> createState() => _AskState();
}

class _AskState extends State<_Ask> {
  String result = 'none';
  @override
  Widget build(BuildContext context) => Scaffold(
        body: Column(children: [
          TextButton(
            onPressed: () async {
              final ok = await askPin(context, context.read<ProfilesState>());
              setState(() => result = ok ? 'ok' : 'no');
            },
            child: const Text('ask'),
          ),
          Text('result: $result'),
        ]),
      );
}

void main() {
  group('the PIN pad', () {
    testWidgets('accepts the right PIN and closes', (t) async {
      await pump(t, const _Ask(), setup: (p) => p.setPin('1234'));
      await t.tap(find.text('ask'));
      await t.pumpAndSettle();
      expect(find.text('Enter PIN'), findsOneWidget);
      await typePin(t, '1234');
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.text('result: ok'), findsOneWidget);
    });

    testWidgets('a wrong PIN says so, clears and stays open', (t) async {
      await pump(t, const _Ask(), setup: (p) => p.setPin('1234'));
      await t.tap(find.text('ask'));
      await t.pumpAndSettle();
      await typePin(t, '9999');
      expect(find.text('Wrong PIN'), findsOneWidget);
      expect(find.byType(AlertDialog), findsOneWidget);
      await typePin(t, '1234');
      expect(find.text('result: ok'), findsOneWidget);
    });

    testWidgets('Cancel gives a no', (t) async {
      await pump(t, const _Ask(), setup: (p) => p.setPin('1234'));
      await t.tap(find.text('ask'));
      await t.pumpAndSettle();
      await t.tap(find.bySemanticsLabel('Cancel'));
      await t.pumpAndSettle();
      expect(find.text('result: no'), findsOneWidget);
    });

    testWidgets('digits typed on a keyboard work too', (t) async {
      await pump(t, const _Ask(), setup: (p) => p.setPin('2580'));
      await t.tap(find.text('ask'));
      await t.pumpAndSettle();
      for (final d in ['2', '5', '8', '0']) {
        await t.sendKeyEvent(
            LogicalKeyboardKey.findKeyByKeyId(0x00000000030 + int.parse(d)) ??
                LogicalKeyboardKey.digit0,
            character: d);
      }
      await t.pumpAndSettle();
      expect(find.text('result: ok'), findsOneWidget);
    });

    testWidgets('too many wrong PINs lock it out with a countdown message',
        (t) async {
      await pump(t, const _Ask(), setup: (p) => p.setPin('1234'));
      await t.tap(find.text('ask'));
      await t.pumpAndSettle();
      for (var i = 0; i < ProfilesState.maxFails; i++) {
        await typePin(t, '0000');
      }
      expect(find.textContaining('Too many tries'), findsOneWidget);
      await typePin(t, '1234');
      expect(
          find.byType(AlertDialog), findsOneWidget); // even the right PIN waits
    });
  });

  group('locked settings', () {
    testWidgets(
        'a Kids profile with a PIN shows a lock until the PIN is entered',
        (t) async {
      await pump(t, const Scaffold(body: SettingsScreen()), setup: (p) {
        p.setPin('1234');
        p.select(p.add('Sam', kids: true).id);
      });
      expect(find.text('Settings are locked'), findsOneWidget);
      expect(find.text('Source & library'), findsNothing);
      await t.tap(find.text('Enter PIN'));
      await t.pumpAndSettle();
      await typePin(t, '1234');
      expect(find.text('Settings are locked'), findsNothing);
      expect(find.text('Source & library'), findsWidgets);
    });

    testWidgets('a Kids profile without a PIN is not locked', (t) async {
      await pump(t, const Scaffold(body: SettingsScreen()),
          setup: (p) => p.select(p.add('Sam', kids: true).id));
      expect(find.text('Settings are locked'), findsNothing);
      expect(find.text('Profiles & PIN'), findsOneWidget);
    });

    testWidgets('the Main profile is never locked', (t) async {
      await pump(t, const Scaffold(body: SettingsScreen()),
          setup: (p) => p.setPin('1234'));
      expect(find.text('Settings are locked'), findsNothing);
    });
  });

  group('Profiles & PIN settings', () {
    testWidgets('lists the profiles and adds one', (t) async {
      await pump(t, const Scaffold(body: SettingsScreen()));
      await t.tap(find.text('Profiles & PIN'));
      await t.pumpAndSettle();
      expect(find.text('Main  ·  in use'), findsOneWidget);
      await t.tap(find.text('Add a profile'));
      await t.pumpAndSettle();
      await t.enterText(find.byType(TextField), 'Sam');
      await t.tap(find.text('Kids profile'));
      await t.tap(find.text('Add'));
      await t.pumpAndSettle();
      expect(ps.profiles.map((e) => e.name), ['Main', 'Sam']);
      expect(ps.profiles.last.kids, isTrue);
      expect(find.text('Sam'), findsOneWidget);
    });

    testWidgets('sets a PIN by typing it twice', (t) async {
      await pump(t, const Scaffold(body: SettingsScreen()));
      await t.tap(find.text('Profiles & PIN'));
      await t.pumpAndSettle();
      await t.tap(find.text('Set a PIN'));
      await t.pumpAndSettle();
      await typePin(t, '1357');
      expect(find.text('Enter it again'), findsOneWidget);
      await typePin(t, '1357');
      expect(ps.hasPin, isTrue);
      expect(ps.checkPin('1357'), PinResult.ok);
      expect(find.text('Change PIN'), findsOneWidget);
    });

    testWidgets('a PIN typed differently the second time is refused',
        (t) async {
      await pump(t, const Scaffold(body: SettingsScreen()));
      await t.tap(find.text('Profiles & PIN'));
      await t.pumpAndSettle();
      await t.tap(find.text('Set a PIN'));
      await t.pumpAndSettle();
      await typePin(t, '1357');
      await typePin(t, '1358');
      expect(find.text('The two PINs do not match'), findsOneWidget);
      expect(ps.hasPin, isFalse);
    });

    testWidgets('removing the PIN asks for it first', (t) async {
      await pump(t, const Scaffold(body: SettingsScreen()),
          setup: (p) => p.setPin('1234'));
      await t.tap(find.text('Profiles & PIN'));
      await t.pumpAndSettle();
      await t.tap(find.text('Remove PIN'));
      await t.pumpAndSettle();
      await typePin(t, '0000');
      expect(ps.hasPin, isTrue);
      await typePin(t, '1234');
      expect(ps.hasPin, isFalse);
    });
  });

  group("Who's watching", () {
    testWidgets('shows everyone and switches on a tap', (t) async {
      await pump(t, const ProfilePickerScreen(), setup: (p) => p.add('Sam'));
      expect(find.text("Who's watching?"), findsOneWidget);
      expect(find.text('Main'), findsOneWidget);
      await t.tap(find.text('Sam'));
      await t.pumpAndSettle();
      expect(ps.current.name, 'Sam');
      expect(ps.needsPick, isFalse);
    });

    testWidgets('leaving a Kids profile needs the PIN', (t) async {
      await pump(t, const ProfilePickerScreen(), setup: (p) {
        p.setPin('1234');
        p.select(p.add('Sam', kids: true).id);
      });
      await t.tap(find.text('Main'));
      await t.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      await typePin(t, '0000');
      expect(ps.current.name, 'Sam');
      await typePin(t, '1234');
      expect(ps.current.name, 'Main');
    });

    testWidgets('a locked profile needs the PIN to open', (t) async {
      await pump(t, const ProfilePickerScreen(), setup: (p) {
        p.setPin('1234');
        final d = p.add('Dad');
        p.update(d.copyWith(locked: true));
      });
      await t.tap(find.text('Dad'));
      await t.pumpAndSettle();
      await typePin(t, '1234');
      expect(ps.current.name, 'Dad');
    });
  });
}
