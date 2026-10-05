import 'package:media_kit/media_kit.dart';

/// Native platforms: tune libmpv's demuxer cache from the buffer preset.
Future<void> applyBuffer(Player player, int cacheSecs) async {
  final plat = player.platform;
  if (plat is NativePlayer) {
    await plat.setProperty('cache', 'yes');
    await plat.setProperty('cache-secs', '$cacheSecs');
  }
}
