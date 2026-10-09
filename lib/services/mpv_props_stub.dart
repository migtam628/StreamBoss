import 'package:media_kit/media_kit.dart';
import 'chapters.dart';

/// Web: libmpv properties are not available.
Future<void> applyBuffer(Player player, int cacheSecs) async {}

/// Web: user shaders are not supported.
Future<void> applyShaders(Player player, List<MapEntry<String, String>> idAndSource) async {}

bool get shadersSupported => false;

/// Web: the browser decides languages and the User-Agent.
Future<void> applyPlaybackPrefs(
  Player player, {
  required String audioLang,
  required String subLang,
  required bool subsOn,
  required String userAgent,
}) async {}

/// Web: the browser picks the quality.
Future<void> applyPreview(Player player) async {}

/// Web: the browser keeps what it keeps.
Future<void> allowRewind(Player player, int megabytes) async {}

/// Web: the browser does not tell us about chapters.
Future<List<Chapter>> readChapters(Player player) async => const [];
