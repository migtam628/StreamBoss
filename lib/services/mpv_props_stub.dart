import 'package:media_kit/media_kit.dart';

/// Web: libmpv properties are not available.
Future<void> applyBuffer(Player player, int cacheSecs) async {}

/// Web: user shaders are not supported.
Future<void> applyShaders(Player player, List<MapEntry<String, String>> idAndSource) async {}

bool get shadersSupported => false;
