import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:streamboss/services/watch_logic.dart';
import 'package:streamboss/state/settings_state.dart';

VideoTrack track(String id, int? w, int? h, {int? bitrate}) =>
    VideoTrack(id, null, null, w: w, h: h, bitrate: bitrate);

void main() {
  group('quality menu', () {
    test('a stream with several sizes: Auto, then the sizes, biggest first',
        () {
      final c = qualityChoices([
        VideoTrack.auto(),
        VideoTrack.no(),
        track('1', 1280, 720),
        track('2', 1920, 1080),
        track('3', 640, 360),
      ]);
      expect(c.map((e) => e.label), ['Auto', '1080p', '720p', '360p']);
      expect(c.first.track, isNull);
      expect(c[1].track!.id, '2');
    });

    test('4K is named 4K', () {
      final c =
          qualityChoices([track('1', 3840, 2160), track('2', 1920, 1080)]);
      expect(c.map((e) => e.label), ['Auto', '4K', '1080p']);
    });

    test('two tracks of one size are one entry, the one with more data', () {
      final c = qualityChoices([
        track('a', 1920, 1080, bitrate: 3000000),
        track('b', 1920, 1080, bitrate: 6000000),
        track('c', 1280, 720),
      ]);
      expect(c.map((e) => e.label), ['Auto', '1080p', '720p']);
      expect(c[1].track!.id, 'b');
    });

    test('a plain file has nothing to choose, so no menu', () {
      expect(qualityChoices(const []), isEmpty);
      expect(qualityChoices([VideoTrack.auto(), VideoTrack.no()]), isEmpty);
      expect(
          qualityChoices([VideoTrack.auto(), track('1', 1920, 1080)]), isEmpty);
      expect(qualityChoices([track('1', null, null), track('2', null, 0)]),
          isEmpty);
    });

    test('which entry has the tick', () {
      final c = qualityChoices([track('1', 1920, 1080), track('2', 1280, 720)]);
      expect(qualityIsCurrent(c[0], VideoTrack.auto()), isTrue);
      expect(qualityIsCurrent(c[1], VideoTrack.auto()), isFalse);
      expect(qualityIsCurrent(c[1], c[1].track), isTrue);
      expect(qualityIsCurrent(c[2], c[1].track), isFalse);
      expect(qualityIsCurrent(c[0], c[1].track), isFalse);
    });
  });

  group('pause when you leave', () {
    LeaveAction act(AppLifecycleState s,
            {bool on = true, bool playing = true, bool ours = false}) =>
        leaveAction(state: s, enabled: on, playing: playing, pausedByUs: ours);

    test('hidden or in the background pauses a playing video', () {
      expect(act(AppLifecycleState.hidden), LeaveAction.pause);
      expect(act(AppLifecycleState.paused), LeaveAction.pause);
    });

    test('losing focus alone does not pause (a second monitor is fine)', () {
      expect(act(AppLifecycleState.inactive), LeaveAction.none);
    });

    test('coming back plays again, but only after a pause made here', () {
      expect(act(AppLifecycleState.resumed, playing: false, ours: true),
          LeaveAction.resume);
      expect(act(AppLifecycleState.resumed, playing: false, ours: false),
          LeaveAction.none);
    });

    test('a video already paused is left alone', () {
      expect(act(AppLifecycleState.hidden, playing: false), LeaveAction.none);
    });

    test('off does nothing', () {
      expect(act(AppLifecycleState.hidden, on: false), LeaveAction.none);
      expect(
          act(AppLifecycleState.resumed, on: false, playing: false, ours: true),
          LeaveAction.none);
    });

    test('the setting is off until it is turned on', () async {
      SharedPreferences.setMockInitialValues({});
      final st = SettingsState();
      await st.init();
      expect(st.pauseOnLeave, isFalse);
      st.set('pauseOnLeave', true);
      expect(st.pauseOnLeave, isTrue);
    });
  });
}
