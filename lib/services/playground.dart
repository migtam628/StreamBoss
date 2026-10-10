import 'package:flutter/material.dart';
import '../models/media.dart';
import 'library_view.dart';

/// The six tiles on Playground's Home and what each one holds.
enum PlayTile {
  cartoons('Cartoons', Icons.mood, Color(0xFFFF5A5F), false),
  movies('Movies', Icons.movie_outlined, Color(0xFF7C5CFF), false),
  songs('Songs', Icons.music_note, Color(0xFF2FB8CC), false),
  learn('Learn', Icons.auto_awesome, Color(0xFF3FC46A), false),
  favorites('Favorites', Icons.star_border, Color(0xFFFFD23F), true),
  sleepy('Sleepy time', Icons.bedtime_outlined, Color(0xFFFF9F45), false);

  final String label;
  final IconData icon;
  final Color color;

  /// Light tiles take dark text.
  final bool dark;
  const PlayTile(this.label, this.icon, this.color, this.dark);
}

final _cartoon = RegExp(r'cartoon|animat|anime|toon', caseSensitive: false);
final _songs =
    RegExp(r'music|song|nursery|rhyme|karaoke|sing', caseSensitive: false);
final _learn = RegExp(
    r'educat|learn|science|nature|animal|school|abc|number|documentar',
    caseSensitive: false);
final _sleepy = RegExp(r'sleep|lullab|calm|bedtime|relax|stor(y|ies)',
    caseSensitive: false);

/// Everything in [c] that sits in a category that looks made for children.
List<MediaItem> kidsItems(Catalog c) {
  final ok = <String>{
    for (final cat in [
      ...c.liveCategories,
      ...c.movieCategories,
      ...c.seriesCategories
    ])
      if (isKidsCategory(cat.name)) cat.id
  };
  return [
    for (final i in [...c.movies, ...c.series, ...c.live])
      if (ok.contains(i.categoryId)) i
  ];
}

/// The titles behind a tile. Only children's categories are ever used, matched by name, so this is as
/// good as the provider's category names.
List<MediaItem> playgroundItems(
    PlayTile t, Catalog c, Set<String> favoriteKeys) {
  final names = <String, String>{
    for (final cat in [
      ...c.liveCategories,
      ...c.movieCategories,
      ...c.seriesCategories
    ])
      cat.id: cat.name,
  };
  final kids = kidsItems(c);
  bool cat(MediaItem i, RegExp r) =>
      r.hasMatch(names[i.categoryId] ?? '') || r.hasMatch(i.name);
  switch (t) {
    case PlayTile.cartoons:
      return [
        for (final i in kids)
          if (cat(i, _cartoon) || i.kind == MediaKind.series) i
      ];
    case PlayTile.movies:
      return [
        for (final i in kids)
          if (i.kind == MediaKind.movie) i
      ];
    case PlayTile.songs:
      return [
        for (final i in kids)
          if (cat(i, _songs)) i
      ];
    case PlayTile.learn:
      return [
        for (final i in kids)
          if (cat(i, _learn)) i
      ];
    case PlayTile.favorites:
      return [
        for (final i in kids)
          if (favoriteKeys.contains(i.key)) i
      ];
    case PlayTile.sleepy:
      return [
        for (final i in kids)
          if (cat(i, _sleepy)) i
      ];
  }
}

/// Bedtime settings are 'off' or 'HH:MM'. Waking time is 5 in the morning.
DateTime? _bed(DateTime now, String setting) {
  final m = RegExp(r'^(\d{1,2}):(\d{2})$').firstMatch(setting);
  if (m == null) return null;
  return DateTime(now.year, now.month, now.day, int.parse(m.group(1)!),
      int.parse(m.group(2)!));
}

/// True from bedtime until 5 in the morning. Always false when bedtime is off.
bool pastBedtime(DateTime now, String setting) {
  final bed = _bed(now, setting);
  if (bed == null) return false;
  return !now.isBefore(bed) || now.hour < 5;
}

/// Time left before bedtime tonight, or null when it is off or already past.
Duration? untilBedtime(DateTime now, String setting) {
  final bed = _bed(now, setting);
  if (bed == null || pastBedtime(now, setting)) return null;
  return bed.difference(now);
}

String bedtimeLabel(Duration d) {
  final m = d.inMinutes;
  if (m < 1) return 'Bedtime now';
  return m >= 60
      ? 'Bedtime in ${m ~/ 60} h ${m % 60} min'
      : 'Bedtime in $m min';
}
