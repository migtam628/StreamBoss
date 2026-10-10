import 'package:flutter_test/flutter_test.dart';
import 'package:streamboss/models/media.dart';
import 'package:streamboss/services/details_logic.dart';
import 'package:streamboss/services/tmdb.dart';
import 'package:streamboss/services/xtream_client.dart';

MediaItem m(String id, String name, {String cat = '1', String? rating, MediaKind kind = MediaKind.movie}) =>
    MediaItem(id: id, name: name, kind: kind, categoryId: cat, rating: rating, streamUrl: 'http://x/$id');

void main() {
  test('runtime reads like people say it', () {
    expect(formatRuntime(108), '1h 48m');
    expect(formatRuntime(52), '52m');
    expect(formatRuntime(120), '2h');
    expect(formatRuntime(0), '');
  });

  test('quality tags', () {
    expect(qualityTagOf('Harbor Lights 4K'), '4K');
    expect(qualityTagOf('Harbor Lights (2021) FHD'), '1080p');
    expect(qualityTagOf('Harbor Lights 720p'), '720p');
    expect(qualityTagOf('Harbor Lights'), isNull);
  });

  group('versions and similar', () {
    final lib = [
      m('1', 'EN - Harbor Lights (2021) 720p'),
      m('2', 'EN - Harbor Lights (2021) 4K', cat: '2'),
      m('3', 'Harbor Lights 2021 FHD', cat: '3'),
      m('4', 'Harbor Lights 1999'),
      m('5', 'Harbor Nights 2021'),
      m('6', 'Harbor Lights (2021)', kind: MediaKind.series),
    ];
    test('other copies of the same title, best quality first', () {
      final v = versionsOf(lib[0], lib);
      expect(v.map((e) => e.id), ['2', '3']);
    });
    test('a different year or another kind is not a copy', () {
      expect(versionsOf(lib[3], lib), isEmpty);
      expect(versionsOf(lib[5], lib), isEmpty);
    });
    test('similar: same category, best rated first, never itself', () {
      final cat = [
        m('a', 'A', rating: '5'),
        m('b', 'B', rating: '8'),
        m('c', 'C', rating: '7'),
        m('d', 'D', cat: '9', rating: '9'),
      ];
      expect(similarTo(cat[0], cat).map((e) => e.id), ['b', 'c']);
      expect(similarTo(cat[0], cat, limit: 1).map((e) => e.id), ['b']);
    });
  });

  group('next up', () {
    test('the first episode when nothing is started', () {
      expect(nextUpIndex([false, false], [false, false]), 0);
    });
    test('partway through an episode continues it', () {
      expect(nextUpIndex([true, true, false, false], [false, false, true, false]), 2);
    });
    test('after a finished episode comes the next one', () {
      expect(nextUpIndex([true, true, false], [false, false, false]), 2);
    });
    test('everything watched has no next', () {
      expect(nextUpIndex([true, true], [false, false]), isNull);
      expect(nextUpIndex(const [], const []), isNull);
    });
  });

  test('a new episode is one from the last two weeks', () {
    final now = DateTime(2026, 10, 10);
    expect(isRecentEpisode('2026-10-03', now: now), isTrue);
    expect(isRecentEpisode('2026-09-01', now: now), isFalse);
    expect(isRecentEpisode('2026-11-01', now: now), isFalse);
    expect(isRecentEpisode(null, now: now), isFalse);
    expect(isRecentEpisode('soon', now: now), isFalse);
  });

  group('provider info', () {
    test('movie: genres, director, age, and what the file is', () {
      final t = XtreamClient.parseInfo({
        'info': {
          'plot': 'p',
          'genre': 'Drama, Romance',
          'director': 'Mara Voss',
          'country': 'Spain',
          'mpaa_rating': 'PG-13',
          'bitrate': 4500,
          'video': {'codec_name': 'hevc', 'width': 1920, 'height': 1080},
          'audio': {'codec_name': 'eac3', 'channels': 6, 'tags': {'language': 'eng'}},
        },
        'movie_data': {'container_extension': 'mkv'},
      })!;
      expect(t.genres, ['Drama', 'Romance']);
      expect(t.directors, ['Mara Voss']);
      expect(t.certification, 'PG-13');
      expect(t.tech!.resolution, '1080p');
      expect(t.tech!.channels, '5.1');
      expect(t.tech!.container, 'mkv');
      expect(t.tech!.bitrateKbps, 4500);
    });
    test('a bare plot still parses, with no tech', () {
      final t = XtreamClient.parseInfo({'info': {'plot': 'only a plot'}})!;
      expect(t.tech, isNull);
      expect(t.genres, isEmpty);
    });
    test('episode length from seconds or from a clock', () {
      expect(XtreamClient.episodeMinutes({'duration_secs': 2460}), 41);
      expect(XtreamClient.episodeMinutes({'duration': '00:41:10'}), 41);
      expect(XtreamClient.episodeMinutes({'duration': '41'}), 41);
      expect(XtreamClient.episodeMinutes({}), isNull);
    });
  });

  test('merging keeps the first source and fills the gaps', () {
    final a = const TmdbInfo(genres: ['Drama'], certification: 'R');
    final b = const TmdbInfo(genres: ['Other'], directors: ['X'], certification: 'PG', tech: TechInfo(container: 'mp4'));
    final r = mergeInfo(a, b)!;
    expect(r.genres, ['Drama']);
    expect(r.directors, ['X']);
    expect(r.certification, 'R');
    expect(r.tech!.container, 'mp4');
  });

  test('TMDB age rating prefers the US one', () {
    expect(
        certificationOf({
          'release_dates': {
            'results': [
              {'iso_3166_1': 'ES', 'release_dates': [{'certification': '12'}]},
              {'iso_3166_1': 'US', 'release_dates': [{'certification': ''}, {'certification': 'PG-13'}]},
            ]
          }
        }, 'movie'),
        'PG-13');
    expect(certificationOf({'content_ratings': {'results': [{'iso_3166_1': 'GB', 'rating': '15'}]}}, 'tv'), '15');
    expect(certificationOf({}, 'movie'), isNull);
  });
}
