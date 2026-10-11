import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:streamboss/services/voice_input.dart';
import 'package:streamboss/theme.dart';
import 'package:streamboss/widgets/voice_search.dart';

class FakeVoice implements VoiceInput {
  final bool available;
  void Function(String, bool)? onWords;
  bool stopped = false;
  bool cancelled = false;
  FakeVoice({this.available = true});
  @override
  Future<bool> start({
    required void Function(String words, bool done) onWords,
    void Function(String message)? onError,
    String? localeId,
  }) async {
    this.onWords = onWords;
    if (!available) onError?.call('Voice search is not available on this device.');
    return available;
  }

  @override
  Future<void> stop() async => stopped = true;
  @override
  Future<void> cancel() async => cancelled = true;
}

Future<void> openDialog(WidgetTester t, FakeVoice v, List<String?> results) async {
  makeVoiceInput = () => v;
  await t.pumpWidget(MaterialApp(
    theme: Boss.theme(),
    home: Builder(
      builder: (c) => Scaffold(
        body: TextButton(onPressed: () async => results.add(await askByVoice(c)), child: const Text('open')),
      ),
    ),
  ));
  await t.tap(find.text('open'));
  await t.pump();
  await t.pump();
}

void main() {
  tearDown(() => makeVoiceInput = SpeechVoiceInput.new);

  testWidgets('words appear as they are heard and the final result is returned', (t) async {
    final v = FakeVoice();
    final got = <String?>[];
    await openDialog(t, v, got);
    expect(find.text('Listening…'), findsOneWidget);
    v.onWords!('the ma', false);
    await t.pump();
    expect(find.text('the ma'), findsOneWidget);
    v.onWords!('  the matrix ', true);
    await t.pumpAndSettle();
    expect(got, ['the matrix']);
    expect(find.text('Listening…'), findsNothing);
    expect(v.cancelled, isTrue);
  });

  testWidgets('Cancel returns nothing', (t) async {
    final v = FakeVoice();
    final got = <String?>[];
    await openDialog(t, v, got);
    await t.tap(find.text('Cancel'));
    await t.pumpAndSettle();
    expect(got, [null]);
  });

  testWidgets('Done uses the words heard so far', (t) async {
    final v = FakeVoice();
    final got = <String?>[];
    await openDialog(t, v, got);
    v.onWords!('news', false);
    await t.pump();
    await t.tap(find.text('Done'));
    await t.pump(const Duration(milliseconds: 500));
    await t.pumpAndSettle();
    expect(v.stopped, isTrue);
    expect(got, ['news']);
  });

  testWidgets('when speech is not available the dialog says so', (t) async {
    final v = FakeVoice(available: false);
    final got = <String?>[];
    await openDialog(t, v, got);
    expect(find.text('Voice search is not available on this device.'), findsOneWidget);
    expect(find.text('Done'), findsNothing);
    await t.tap(find.text('Close'));
    await t.pumpAndSettle();
    expect(got, [null]);
  });

  testWidgets('the microphone button only shows where voice search can work', (t) async {
    try {
      debugDefaultTargetPlatformOverride = TargetPlatform.linux;
      await t.pumpWidget(MaterialApp(theme: Boss.theme(), home: Scaffold(body: VoiceButton(onWords: (_) {}))));
      expect(find.byIcon(Icons.mic_none), findsNothing);
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      await t.pumpWidget(MaterialApp(theme: Boss.theme(), home: Scaffold(body: VoiceButton(onWords: (_) {}))));
      expect(find.byIcon(Icons.mic_none), findsOneWidget);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });
}
