enum MediaKind { live, movie, series }

class Category {
  final String id;
  final String name;
  const Category(this.id, this.name);
}

class MediaItem {
  final String id;
  final String name;
  final MediaKind kind;
  final String? streamUrl; // null for series (resolved via episodes)
  final String? poster;
  final String categoryId;
  final String? rating;
  final String? plot;
  final String? epgId; // XMLTV channel id (tvg-id / epg_channel_id)

  const MediaItem({
    required this.id,
    required this.name,
    required this.kind,
    this.streamUrl,
    this.poster,
    this.categoryId = '',
    this.rating,
    this.plot,
    this.epgId,
  });

  String get key => '${kind.name}:$id';

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'kind': kind.name,
        'url': streamUrl,
        'poster': poster,
        'cat': categoryId,
        'rating': rating,
        'plot': plot,
        'epg': epgId,
      };

  factory MediaItem.fromJson(Map<String, dynamic> j) => MediaItem(
        id: j['id'] as String,
        name: j['name'] as String,
        kind: MediaKind.values.byName(j['kind'] as String),
        streamUrl: j['url'] as String?,
        poster: j['poster'] as String?,
        categoryId: (j['cat'] as String?) ?? '',
        rating: j['rating'] as String?,
        plot: j['plot'] as String?,
        epgId: j['epg'] as String?,
      );
}

class Episode {
  final String id;
  final int season;
  final int number;
  final String title;
  final String url;
  const Episode(this.id, this.season, this.number, this.title, this.url);
}

class Catalog {
  final List<Category> liveCategories, movieCategories, seriesCategories;
  final List<MediaItem> live, movies, series;
  final String? epgUrl; // XMLTV url advertised by the playlist (M3U url-tvg)
  const Catalog({
    this.liveCategories = const [],
    this.movieCategories = const [],
    this.seriesCategories = const [],
    this.live = const [],
    this.movies = const [],
    this.series = const [],
    this.epgUrl,
  });

  List<Category> categoriesFor(MediaKind k) => switch (k) {
        MediaKind.live => liveCategories,
        MediaKind.movie => movieCategories,
        MediaKind.series => seriesCategories,
      };

  List<MediaItem> itemsFor(MediaKind k) => switch (k) {
        MediaKind.live => live,
        MediaKind.movie => movies,
        MediaKind.series => series,
      };

  List<MediaItem> get all => [...live, ...movies, ...series];
}

enum SourceType { xtream, m3u, demo }

class Source {
  final String name;
  final SourceType type;
  final String url; // server base URL (xtream) or playlist URL (m3u)
  final String username;
  final String password;

  const Source({
    required this.name,
    required this.type,
    this.url = '',
    this.username = '',
    this.password = '',
  });

  static const demo = Source(name: 'Demo', type: SourceType.demo);

  Map<String, dynamic> toJson() => {
        'name': name,
        'type': type.name,
        'url': url,
        'user': username,
        'pass': password,
      };

  factory Source.fromJson(Map<String, dynamic> j) => Source(
        name: j['name'] as String,
        type: SourceType.values.byName(j['type'] as String),
        url: (j['url'] as String?) ?? '',
        username: (j['user'] as String?) ?? '',
        password: (j['pass'] as String?) ?? '',
      );
}
