import 'package:flutter_test/flutter_test.dart';
import 'package:streamboss/services/chapters.dart';

void main() {
  group('parseChapters', () {
    test('reads libmpv\'s list, in order', () {
      final c = parseChapters(
          '[{"title":"Credits","time":2400.5},{"title":"Intro","time":0.0},{"title":"Part 1","time":95}]');
      expect(c.map((e) => e.title), ['Intro', 'Part 1', 'Credits']);
      expect(c[2].start, const Duration(minutes: 40, milliseconds: 500));
    });

    test('names the ones that have no title', () {
      final c = parseChapters('[{"time":0},{"title":"","time":60}]');
      expect(c.map((e) => e.title), ['Chapter 1', 'Chapter 2']);
    });

    test('gives none for nothing, nonsense or a different shape', () {
      expect(parseChapters(null), isEmpty);
      expect(parseChapters(''), isEmpty);
      expect(parseChapters('not json'), isEmpty);
      expect(parseChapters('{"a":1}'), isEmpty);
      expect(parseChapters('[1,2,{"title":"x"}]'), isEmpty);
    });
  });

  group('skipHintAt', () {
    const total = Duration(minutes: 45);
    final cs = [
      const Chapter('Recap', Duration.zero),
      const Chapter('Opening', Duration(minutes: 1)),
      const Chapter('Act 1', Duration(minutes: 2)),
      const Chapter('Act 2', Duration(minutes: 20)),
      const Chapter('End Credits', Duration(minutes: 42)),
    ];

    test('offers to skip an intro and lands on the next chapter', () {
      final h = skipHintAt(cs, const Duration(seconds: 20), total)!;
      expect(h.kind, SkipKind.intro);
      expect(h.to, const Duration(minutes: 1));
      expect(h.label, 'Skip intro');
      expect(skipHintAt(cs, const Duration(minutes: 1, seconds: 10), total)!.to,
          const Duration(minutes: 2));
    });

    test('offers to skip the credits and lands on the end when they are last',
        () {
      final h = skipHintAt(cs, const Duration(minutes: 43), total)!;
      expect(h.kind, SkipKind.credits);
      expect(h.to, total);
      expect(h.label, 'Skip credits');
    });

    test('offers nothing in the story, or in a chapter that is about to end',
        () {
      expect(skipHintAt(cs, const Duration(minutes: 5), total), isNull);
      expect(skipHintAt(cs, const Duration(minutes: 1, seconds: 59), total),
          isNull);
      expect(skipHintAt(cs, const Duration(minutes: 44, seconds: 59), total),
          isNull);
    });

    test('nothing without chapters or with plain numbered ones', () {
      expect(skipHintAt(const [], const Duration(seconds: 5), total), isNull);
      expect(
          skipHintAt([
            const Chapter('Chapter 1', Duration.zero),
            const Chapter('Chapter 2', Duration(minutes: 10))
          ], const Duration(seconds: 5), total),
          isNull);
    });
  });
}
