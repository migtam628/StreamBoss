import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:streamboss/state/settings_state.dart';
import 'package:streamboss/widgets/screensaver.dart';

Widget _app({Duration after = const Duration(minutes: 5), Widget? child}) =>
    MaterialApp(
      home: IdleScreensaver(
        after: after,
        check: const Duration(seconds: 1),
        view: (_) => const ColoredBox(
            color: Colors.black, child: Center(child: Text('SAVER'))),
        child: child ?? const Scaffold(body: Center(child: Text('APP'))),
      ),
    );

void main() {
  setUp(() => Screensaver.busy.value = 0);

  testWidgets('starts after the idle time and not before', (t) async {
    await t.pumpWidget(_app());
    await t.pump(const Duration(minutes: 4));
    expect(find.text('SAVER'), findsNothing);
    await t.pump(const Duration(minutes: 2));
    expect(find.text('SAVER'), findsOneWidget);
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('touch wakes it', (t) async {
    await t.pumpWidget(_app());
    await t.pump(const Duration(minutes: 6));
    expect(find.text('SAVER'), findsOneWidget);
    await t.tap(find.text('SAVER'));
    await t.pump();
    expect(find.text('SAVER'), findsNothing);
    expect(find.text('APP'), findsOneWidget);
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('a key press wakes it and is swallowed', (t) async {
    await t.pumpWidget(_app());
    await t.pump(const Duration(minutes: 6));
    expect(find.text('SAVER'), findsOneWidget);
    await t.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await t.pump();
    expect(find.text('SAVER'), findsNothing);
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('input keeps resetting the clock', (t) async {
    await t.pumpWidget(_app());
    for (var i = 0; i < 4; i++) {
      await t.pump(const Duration(minutes: 3));
      await t.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    }
    expect(find.text('SAVER'), findsNothing);
    await t.pumpWidget(const SizedBox());
  });

  testWidgets(
      'never starts while something is playing, and ends if playback starts',
      (t) async {
    Screensaver.busy.value = 1;
    await t.pumpWidget(_app());
    await t.pump(const Duration(minutes: 30));
    expect(find.text('SAVER'), findsNothing);
    Screensaver.busy.value = 0;
    await t.pump(const Duration(minutes: 6));
    expect(find.text('SAVER'), findsOneWidget);
    Screensaver.busy.value = 1;
    await t.pump();
    expect(find.text('SAVER'), findsNothing);
    Screensaver.busy.value = 0;
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('zero minutes turns it off', (t) async {
    await t.pumpWidget(_app(after: Duration.zero));
    await t.pump(const Duration(hours: 3));
    expect(find.text('SAVER'), findsNothing);
    await t.pumpWidget(const SizedBox());
  });

  test(
      'the setting: auto is off away from a TV, a number is minutes, off is zero',
      () async {
    SharedPreferences.setMockInitialValues({});
    final st = SettingsState();
    await st.init();
    expect(st.screensaverMinutes, 0);
    st.set('screensaver', '10');
    expect(st.screensaverMinutes, 10);
    st.set('screensaver', 'off');
    expect(st.screensaverMinutes, 0);
    st.set('tvMode', 'on');
    st.set('screensaver', 'auto');
    expect(st.screensaverMinutes, 10);
  });

  testWidgets('preview shows it right away', (t) async {
    await t.pumpWidget(_app());
    Screensaver.preview.value++;
    await t.pump();
    expect(find.text('SAVER'), findsOneWidget);
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('the drifting view builds with and without artwork', (t) async {
    for (final imgs in [
      <String>[],
      List.generate(10, (i) => 'http://127.0.0.1:1/p$i.jpg')
    ]) {
      await t.pumpWidget(MaterialApp(
          home: ScreensaverView(images: imgs, clock: () => '9:41 PM')));
      await t.pump(const Duration(seconds: 5));
      expect(find.text('9:41 PM'), findsOneWidget);
      expect(tester(t), isNull);
    }
    await t.pumpWidget(const SizedBox());
  });
}

Object? tester(WidgetTester t) => t.takeException();
