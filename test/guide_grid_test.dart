import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:streamboss/models/media.dart';
import 'package:streamboss/screens/guide_screen.dart';
import 'package:streamboss/services/xmltv.dart';
import 'package:streamboss/state/app_state.dart';
import 'package:streamboss/state/settings_state.dart';

void main() {
  testWidgets('guide grid renders programme cells and empty rows', (tester) async {
    final now = DateTime.now();
    final state = AppState()
      ..guide = XmltvData({
        'ch.a': [
          Programme('Morning Show', now.subtract(const Duration(minutes: 20)), now.add(const Duration(minutes: 40))),
          Programme('Noon News', now.add(const Duration(minutes: 40)), now.add(const Duration(minutes: 100))),
        ],
      }, const {});
    const channels = [
      MediaItem(id: '1', name: 'Channel A', kind: MediaKind.live, streamUrl: 'http://x/1', epgId: 'ch.a'),
      MediaItem(id: '2', name: 'Channel B', kind: MediaKind.live, streamUrl: 'http://x/2'),
    ];
    await tester.binding.setSurfaceSize(const Size(1000, 600));
    await tester.pumpWidget(MaterialApp(
      home: MultiProvider(
        providers: [
          ChangeNotifierProvider<AppState>.value(value: state),
          ChangeNotifierProvider<SettingsState>(create: (_) => SettingsState()),
        ],
        child: const Scaffold(body: GuideGrid(channels: channels)),
      ),
    ));
    await tester.pump();

    expect(find.text('Morning Show'), findsOneWidget);
    expect(find.text('Noon News'), findsOneWidget);
    expect(find.text('Channel B'), findsOneWidget);
    expect(find.text('No guide data'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
