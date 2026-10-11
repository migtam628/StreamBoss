import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:streamboss/models/media.dart';
import 'package:streamboss/services/watch_next.dart';
import 'package:streamboss/state/app_state.dart';
import 'package:streamboss/state/settings_state.dart';

MediaItem film(String id,
        {MediaKind kind = MediaKind.movie,
        String? url = 'http://x/v',
        String? poster}) =>
    MediaItem(
        id: id,
        name: 'Film $id',
        kind: kind,
        categoryId: 'c',
        streamUrl: url,
        poster: poster);

class FakeSink implements WatchNextSink {
  final published = <List<ContinueEntry>>[];
  @override
  bool get supported => true;
  @override
  Future<void> publish(List<ContinueEntry> entries) async =>
      published.add(entries);
}

void main() {
  group('continueEntries', () {
    test(
        'keeps unfinished films and episodes, newest first, and skips live, finished and unknown-length titles',
        () {
      final recents = [
        film('a'),
        film('live', kind: MediaKind.live),
        film('b'),
        film('c'),
        film('d'),
        film('nourl', url: null),
      ];
      final pos = {
        'movie:a': 60000,
        'live:live': 5000,
        'movie:b': 90000,
        'movie:c': 5000,
        'movie:nourl': 1000
      };
      final dur = {
        'movie:a': 600000,
        'movie:b': 90000,
        'live:live': 9,
        'movie:nourl': 5000
      }; // b is at its end; c has no length
      final got = continueEntries(recents, pos, dur);
      expect(got.map((e) => e.item.id), ['a']);
      expect(got.single.progress, closeTo(0.1, 1e-9));
    });

    test('skips what is marked watched and caps the row', () {
      final recents = [for (var i = 0; i < 15; i++) film('f$i')];
      final pos = {for (var i = 0; i < 15; i++) 'movie:f$i': 30000};
      final dur = {for (var i = 0; i < 15; i++) 'movie:f$i': 100000};
      expect(continueEntries(recents, pos, dur).length, 10);
      expect(continueEntries(recents, pos, dur, max: 3).map((e) => e.item.id),
          ['f0', 'f1', 'f2']);
      expect(
          continueEntries(recents, pos, dur, watched: {'movie:f0'})
              .first
              .item
              .id,
          'f1');
    });

    test('the map handed to the platform carries what the home screen needs',
        () {
      final e = ContinueEntry(film('a', poster: 'http://p/a.jpg'), 1000, 4000);
      expect(e.toMap(), {
        'key': 'movie:a',
        'title': 'Film a',
        'poster': 'http://p/a.jpg',
        'position': 1000,
        'duration': 4000
      });
    });
  });

  group('AppState', () {
    Future<(AppState, SettingsState, FakeSink)> boot() async {
      SharedPreferences.setMockInitialValues({});
      final st = SettingsState();
      await st.init();
      final app = AppState()..bindSettings(st);
      await app.init();
      final sink = FakeSink();
      app.watchNext = sink;
      return (app, st, sink);
    }

    test('publishes what is partly watched and nothing when the setting is off',
        () async {
      final (app, st, sink) = await boot();
      final f = film('a');
      app.markWatched(f);
      app.savePosition(
          f, const Duration(minutes: 5), const Duration(minutes: 90));
      expect(app.continueWatching.map((e) => e.item.id), ['a']);
      await app.publishWatchNext();
      expect(sink.published.last.map((e) => e.item.id), ['a']);
      st.set('watchNextRow', false);
      await app.publishWatchNext();
      expect(sink.published.last, isEmpty);
    });

    test('finishing a title takes it off the row', () async {
      final (app, _, sink) = await boot();
      final f = film('a');
      app.markWatched(f);
      app.savePosition(
          f, const Duration(minutes: 5), const Duration(minutes: 90));
      app.savePosition(
          f, const Duration(minutes: 89), const Duration(minutes: 90));
      await app.publishWatchNext();
      expect(sink.published.last, isEmpty);
    });

    test('a title chosen on the home screen is remembered for the app to open',
        () async {
      final (app, _, _) = await boot();
      app.openFromWatchNext('movie:a');
      expect(app.pendingResumeKey, 'movie:a');
    });
  });
}
