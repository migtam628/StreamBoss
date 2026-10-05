import 'dart:io';
import 'package:media_kit/media_kit.dart';
import 'package:path_provider/path_provider.dart';

/// Native platforms: tune libmpv's demuxer cache from the buffer preset.
Future<void> applyBuffer(Player player, int cacheSecs) async {
  final plat = player.platform;
  if (plat is NativePlayer) {
    await plat.setProperty('cache', 'yes');
    await plat.setProperty('cache-secs', '$cacheSecs');
  }
}

bool get shadersSupported => true;

/// Writes each shader to the cache dir and points libmpv's `glsl-shaders` at
/// them (in order). An empty list clears all shaders. Safe to call mid-playback.
Future<void> applyShaders(Player player, List<MapEntry<String, String>> idAndSource) async {
  final plat = player.platform;
  if (plat is! NativePlayer) return;
  final paths = <String>[];
  if (idAndSource.isNotEmpty) {
    final dir = Directory('${(await getTemporaryDirectory()).path}/streamboss_shaders');
    await dir.create(recursive: true);
    for (final e in idAndSource) {
      final safe = e.key.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
      final f = File('${dir.path}/$safe.glsl');
      await f.writeAsString(e.value);
      paths.add(f.path);
    }
  }
  // mpv path-list separator: ';' on Windows, ':' elsewhere.
  await plat.setProperty('glsl-shaders', paths.join(Platform.isWindows ? ';' : ':'));
}
