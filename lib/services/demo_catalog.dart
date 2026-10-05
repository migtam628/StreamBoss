import '../models/media.dart';

/// Offline-friendly demo content using public test streams.
Catalog demoCatalog() {
  const hls = [
    'https://test-streams.mux.dev/x36xhzz/x36xhzz.m3u8',
    'https://bitdash-a.akamaihd.net/s/content/media/Manifest.m3u8',
    'https://devstreaming-cdn.apple.com/videos/streaming/examples/bipbop_4x3/bipbop_4x3_variant.m3u8',
  ];
  const mp4 = [
    'https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/BigBuckBunny.mp4',
    'https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/ElephantsDream.mp4',
    'https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/Sintel.mp4',
  ];
  return Catalog(
    liveCategories: const [Category('demo', 'Demo Channels')],
    movieCategories: const [Category('demo', 'Open Movies')],
    live: [
      for (var i = 0; i < hls.length; i++)
        MediaItem(
          id: 'l$i',
          name: 'Demo Channel ${i + 1}',
          kind: MediaKind.live,
          streamUrl: hls[i],
          categoryId: 'demo',
        ),
    ],
    movies: [
      for (final e in const [
        ['Big Buck Bunny', 0],
        ['Elephants Dream', 1],
        ['Sintel', 2],
      ])
        MediaItem(
          id: 'm${e[1]}',
          name: e[0] as String,
          kind: MediaKind.movie,
          streamUrl: mp4[e[1] as int],
          categoryId: 'demo',
          rating: '7.0',
          plot: 'Blender Foundation open movie (demo content).',
        ),
    ],
  );
}
