import 'dart:async';
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import '../models/media.dart';
import '../state/settings_state.dart';
import '../widgets/screensaver.dart';
import 'mpv_props.dart';

/// What the mini player is playing: the player itself and enough to open the full player again.
class MiniSession {
  final Player player;
  final VideoController controller;

  /// The movie, episode or channel playing now, and the channels being zapped through, if any.
  final MediaItem item;
  final List<MediaItem>? queue;
  final List<MediaItem>? episodes;
  final String title;
  final bool catchUp;
  const MiniSession({
    required this.player,
    required this.controller,
    required this.item,
    required this.title,
    this.queue,
    this.episodes,
    this.catchUp = false,
  });

  bool get live => item.kind == MediaKind.live;
}

/// The corner a dropped mini player settles in, from where it was let go.
/// [x] and [y] are the centre of the window as fractions of the screen (0 to 1).
({bool right, bool bottom}) snapCorner(double x, double y) =>
    (right: x >= 0.5, bottom: y >= 0.5);

/// Picture-in-picture inside the app: a small window that keeps playing while you browse. The player
/// hands its [Player] over (see PlayerScreen) so nothing restarts; the window can be dragged to a
/// corner, expanded back to the full player, or closed.
class MiniPlayer extends ChangeNotifier {
  static final instance = MiniPlayer();

  /// The app's navigator, so the window can open the full player from above the routes.
  static final navigatorKey = GlobalKey<NavigatorState>();

  MiniSession? _session;
  MiniSession? get session => _session;
  bool get active => _session != null;

  /// Shows [s] as the mini player, closing any other one first.
  void start(MiniSession s) {
    final old = _session;
    if (old != null && !identical(old, s)) {
      old.player.dispose();
    } else if (old == null) {
      Screensaver.busy.value++;
    }
    _session = s;
    WakelockPlus.enable().catchError((_) {});
    notifyListeners();
  }

  /// Takes the session away without stopping it, for the full player to carry on with.
  MiniSession? take() {
    final s = _session;
    if (s == null) return null;
    _session = null;
    Screensaver.busy.value--;
    notifyListeners();
    return s;
  }

  /// Stops and removes the mini player.
  Future<void> close() async {
    final s = take();
    if (s == null) return;
    WakelockPlus.disable().catchError((_) {});
    try {
      await s.player.dispose();
    } catch (_) {}
  }

  /// Starts [channel] straight in the mini player, with [queue] to zap through. No full-screen player
  /// is involved. False when the stream could not be started.
  Future<bool> playChannel(SettingsState st, MediaItem channel,
      {List<MediaItem>? queue}) async {
    if (channel.streamUrl == null) return false;
    final live = (queue ?? const <MediaItem>[])
        .where((e) => e.kind == MediaKind.live && e.streamUrl != null)
        .toList();
    final q =
        live.length > 1 && live.any((e) => e.key == channel.key) ? live : null;
    Player? player;
    try {
      player = Player(
          configuration: PlayerConfiguration(
              logLevel: MPVLogLevel.error,
              bufferSize: st.isTv ? 16 * 1024 * 1024 : 32 * 1024 * 1024));
      final controller = VideoController(player,
          configuration: VideoControllerConfiguration(
              enableHardwareAcceleration: st.decoder != 'software'));
      await applyBuffer(player, st.bufferSecs);
      await allowRewind(player, st.isTv ? 24 : 48);
      await applyPlaybackPrefs(player,
          audioLang: st.audioLang,
          subLang: st.subLang,
          subsOn: st.subsOn,
          userAgent: st.userAgent);
      if (q != null) {
        await player.open(Playlist(
          [for (final c in q) Media(c.streamUrl!, httpHeaders: c.headers)],
          index: q.indexWhere((e) => e.key == channel.key),
        ));
      } else {
        await player
            .open(Media(channel.streamUrl!, httpHeaders: channel.headers));
      }
      start(MiniSession(
          player: player,
          controller: controller,
          item: channel,
          title: channel.name,
          queue: q));
      return true;
    } catch (_) {
      try {
        await player?.dispose();
      } catch (_) {}
      return false;
    }
  }
}
