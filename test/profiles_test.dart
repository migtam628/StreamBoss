import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:streamboss/models/media.dart';
import 'package:streamboss/models/profile.dart';
import 'package:streamboss/state/app_state.dart';
import 'package:streamboss/state/profiles_state.dart';

Future<ProfilesState> fresh([Map<String, Object> prefs = const {}]) async {
  SharedPreferences.setMockInitialValues({...prefs});
  final p = ProfilesState();
  await p.init();
  return p;
}

void main() {
  group('profiles', () {
    test('start with one Main profile and no picker', () async {
      final p = await fresh();
      expect(p.profiles.single.id, 'main');
      expect(p.current.name, 'Main');
      expect(p.multiple, isFalse);
      expect(p.needsPick, isFalse);
    });

    test('a second profile brings the picker, until one is chosen', () async {
      final p = await fresh();
      final k = p.add('Sam', kids: true);
      expect(p.needsPick, isTrue);
      p.select(k.id);
      expect(p.needsPick, isFalse);
      expect(p.current.name, 'Sam');
      expect(p.current.kids, isTrue);
    });

    test('they are kept for next time', () async {
      final p = await fresh();
      final k = p.add('Sam', kids: true);
      p.select(k.id);
      p.setPin('1234');
      final again = ProfilesState();
      await again.init();
      expect(again.profiles.map((e) => e.name), ['Main', 'Sam']);
      expect(again.currentId, k.id);
      expect(again.hasPin, isTrue);
      expect(again.checkPin('1234'), PinResult.ok);
    });

    test('a blank name gets a default one; names are trimmed; the limit holds',
        () async {
      final p = await fresh();
      expect(p.add('   ').name, 'Profile 2');
      expect(p.add('  Ann ').name, 'Ann');
      while (p.canAdd) {
        p.add('x');
      }
      expect(p.profiles.length, 8);
    });

    test('deleting moves off the deleted profile and the last one stays',
        () async {
      final p = await fresh();
      final k = p.add('Sam');
      p.select(k.id);
      expect(p.remove(k.id), isTrue);
      expect(p.currentId, 'main');
      expect(p.remove('main'), isFalse);
      expect(p.profiles, hasLength(1));
    });
  });

  group('PIN', () {
    test('is stored hashed, salted and not in the clear', () async {
      final p = await fresh();
      p.setPin('4321');
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('pinHash'), isNot(contains('4321')));
      expect(prefs.getString('pinHash'), hasLength(64));
      final first = prefs.getString('pinSalt');
      p.setPin('4321');
      expect(prefs.getString('pinSalt'), isNot(first));
    });

    test('only four digits are a PIN', () {
      expect(ProfilesState.validPin('1234'), isTrue);
      expect(ProfilesState.validPin('123'), isFalse);
      expect(ProfilesState.validPin('12345'), isFalse);
      expect(ProfilesState.validPin('12a4'), isFalse);
    });

    test('five wrong tries lock it for a while, and even the right PIN waits',
        () async {
      final p = await fresh()
        ..setPin('1234');
      for (var i = 0; i < ProfilesState.maxFails - 1; i++) {
        expect(p.checkPin('0000'), PinResult.wrong);
      }
      expect(p.checkPin('0000'), PinResult.lockedOut);
      expect(p.lockedSeconds, greaterThan(0));
      expect(p.checkPin('1234'), PinResult.lockedOut);
    });

    test('a right PIN resets the count', () async {
      final p = await fresh()
        ..setPin('1234');
      for (var i = 0; i < 3; i++) {
        p.checkPin('0000');
      }
      expect(p.checkPin('1234'), PinResult.ok);
      for (var i = 0; i < ProfilesState.maxFails - 1; i++) {
        expect(p.checkPin('0000'), PinResult.wrong);
      }
    });

    test('with no PIN nothing is checked or locked', () async {
      final p = await fresh();
      expect(p.checkPin('anything'), PinResult.ok);
      final k = p.add('Sam', kids: true);
      p.select(k.id);
      expect(p.settingsLocked, isFalse);
    });

    test('removing it lifts every profile lock', () async {
      final p = await fresh()
        ..setPin('1234');
      final k = p.add('Sam');
      p.update(k.copyWith(locked: true));
      p.clearPin();
      expect(p.hasPin, isFalse);
      expect(p.profiles.any((e) => e.locked), isFalse);
    });
  });

  group('what the PIN guards', () {
    test(
        'settings lock while a Kids profile is in use and open for a while after the PIN',
        () async {
      final p = await fresh()
        ..setPin('1234');
      final k = p.add('Sam', kids: true);
      expect(p.settingsLocked, isFalse); // Main is not a Kids profile
      p.select(k.id);
      expect(p.settingsLocked, isTrue);
      p.openSettings();
      expect(p.settingsLocked, isFalse);
      p.select('main');
      p.select(k.id); // coming back shuts them again
      expect(p.settingsLocked, isTrue);
    });

    test(
        'leaving a Kids profile and opening a locked one need the PIN; the rest do not',
        () async {
      final p = await fresh()
        ..setPin('1234');
      final kids = p.add('Sam', kids: true);
      final locked = p.add('Dad');
      p.update(locked.copyWith(locked: true));
      final plain = p.add('Ann');
      final lockedNow = p.profiles.firstWhere((e) => e.id == locked.id);

      expect(p.needsPinToEnter(kids), isFalse); // from Main to Kids is free
      expect(p.needsPinToEnter(lockedNow), isTrue);
      p.select(kids.id);
      expect(p.needsPinToEnter(p.profiles.firstWhere((e) => e.id == plain.id)),
          isTrue); // leaving Kids
      expect(p.needsPinToEnter(kids), isFalse); // already there
      p.select('main');
      expect(p.needsPinToEnter(p.profiles.firstWhere((e) => e.id == plain.id)),
          isFalse);
    });

    test('without a PIN nothing needs one', () async {
      final p = await fresh();
      final k = p.add('Sam', kids: true);
      p.select(k.id);
      expect(p.needsPinToEnter(Profile.main), isFalse);
    });
  });

  group('personal data per profile', () {
    const movie = MediaItem(
        id: '1', name: 'Film', kind: MediaKind.movie, categoryId: 'c');

    test('Main keeps the old keys, other profiles get their own', () async {
      final p = await fresh({
        'favorites': <String>['movie:old'],
      });
      final app = AppState()..bindProfiles(p);
      await app.init();
      expect(app.favorites, {'movie:old'});

      final k = p.add('Sam', kids: true);
      p.select(k.id);
      expect(app.favorites, isEmpty);
      app.toggleFavorite(movie);
      app.markWatched(movie);
      expect(app.favorites, {'movie:1'});

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getStringList('favorites:${k.id}'), ['movie:1']);
      expect(prefs.getStringList('favorites'), ['movie:old']);
      expect(prefs.getStringList('recents:${k.id}'), hasLength(1));
      expect(prefs.getStringList('recents'), isNull);

      p.select('main');
      expect(app.favorites, {'movie:old'});
      expect(app.recents, isEmpty);
      p.select(k.id);
      expect(app.favorites, {'movie:1'});
      expect(app.recents.single.name, 'Film');
    });

    test('resume positions are separate too', () async {
      final p = await fresh();
      final app = AppState()..bindProfiles(p);
      await app.init();
      app.savePosition(
          movie, const Duration(minutes: 5), const Duration(minutes: 90));
      expect(app.resumeFor(movie), const Duration(minutes: 5));
      final k = p.add('Sam');
      p.select(k.id);
      expect(app.resumeFor(movie), isNull);
    });

    test(
        'a Kids profile sees only kid categories, and Main sees everything again',
        () async {
      final p = await fresh();
      final app = AppState()..bindProfiles(p);
      await app.init();
      app.catalog = const Catalog(
        liveCategories: [Category('1', 'News'), Category('2', 'Kids')],
        live: [
          MediaItem(id: 'a', name: 'A', kind: MediaKind.live, categoryId: '1'),
          MediaItem(id: 'b', name: 'B', kind: MediaKind.live, categoryId: '2'),
        ],
      );
      expect(app.shown.live, hasLength(2));
      final k = p.add('Sam', kids: true);
      p.select(k.id);
      expect(app.shown.live.map((e) => e.name), ['B']);
      p.select('main');
      expect(app.shown.live, hasLength(2));
    });

    test('forgetting a profile removes what it saved', () async {
      final p = await fresh();
      final app = AppState()..bindProfiles(p);
      await app.init();
      final k = p.add('Sam');
      p.select(k.id);
      app.toggleFavorite(movie);
      p.select('main');
      await app.forgetProfile(k.id);
      expect(
          (await SharedPreferences.getInstance())
              .getStringList('favorites:${k.id}'),
          isNull);
    });
  });
}
