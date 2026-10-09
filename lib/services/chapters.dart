import 'dart:convert';

class Chapter {
  final String title;
  final Duration start;
  const Chapter(this.title, this.start);
}

/// libmpv's `chapter-list` as JSON: `[{"title":"Intro","time":0.0}, ...]`. Anything else gives none.
List<Chapter> parseChapters(String? json) {
  if (json == null || json.trim().isEmpty) return const [];
  try {
    final l = jsonDecode(json);
    if (l is! List) return const [];
    final out = <Chapter>[];
    for (final e in l) {
      if (e is! Map) continue;
      final t = (e['time'] as num?)?.toDouble();
      if (t == null || t < 0) continue;
      final title = '${e['title'] ?? ''}'.trim();
      out.add(Chapter(title.isEmpty ? 'Chapter ${out.length + 1}' : title,
          Duration(milliseconds: (t * 1000).round())));
    }
    out.sort((a, b) => a.start.compareTo(b.start));
    return out;
  } catch (_) {
    return const [];
  }
}

enum SkipKind { intro, credits }

class SkipHint {
  final SkipKind kind;

  /// Where skipping lands: the start of the next chapter, or the end of the file.
  final Duration to;
  const SkipHint(this.kind, this.to);

  String get label => kind == SkipKind.intro ? 'Skip intro' : 'Skip credits';
}

final _intro = RegExp(
    r'\b(intro|opening|recap|previously|cold open|prologue|title sequence|theme)\b',
    caseSensitive: false);
final _credits = RegExp(r'\b(credits?|outro|ending|closing|end title)\b',
    caseSensitive: false);

/// The skip button that fits [position]: the chapter being played is named like an intro or like the
/// credits. Null in any other chapter, so a file with plain "Chapter 3" names never shows one.
SkipHint? skipHintAt(
    List<Chapter> chapters, Duration position, Duration total) {
  if (chapters.isEmpty) return null;
  var i = -1;
  for (var k = 0; k < chapters.length; k++) {
    if (chapters[k].start <= position) i = k;
  }
  if (i < 0) return null;
  final title = chapters[i].title;
  final next = i + 1 < chapters.length ? chapters[i + 1].start : total;
  if (next <= position + const Duration(seconds: 2)) {
    return null; // nothing worth skipping
  }
  if (_credits.hasMatch(title)) return SkipHint(SkipKind.credits, next);
  if (_intro.hasMatch(title)) return SkipHint(SkipKind.intro, next);
  return null;
}
