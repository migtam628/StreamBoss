import 'dart:async';
import 'package:cast/cast.dart';
import 'package:flutter/foundation.dart';

/// Casting to a Chromecast or a TV with Chromecast built in. Experimental: it talks the Cast
/// protocol straight to the device (no Google SDK), so it needs the phone and the TV on the same
/// network, and the device fetches the stream itself.
const castAppId = 'CC1AD845'; // Google's Default Media Receiver

/// Casting is not available in a browser (no raw sockets) and needs the plugin's platforms.
bool get castSupported => !kIsWeb;

/// What the Default Media Receiver can be told a stream is, from its address.
String castContentType(String url) {
  final path = (Uri.tryParse(url)?.path ?? url).toLowerCase();
  if (path.endsWith('.m3u8') || path.endsWith('.m3u')) {
    return 'application/x-mpegURL';
  }
  if (path.endsWith('.mpd')) return 'application/dash+xml';
  if (path.endsWith('.mkv')) return 'video/x-matroska';
  if (path.endsWith('.webm')) return 'video/webm';
  if (path.endsWith('.ts')) return 'video/mp2t';
  return 'video/mp4';
}

/// The LOAD request that starts [url] on the receiver.
Map<String, dynamic> castLoadMessage({
  required int requestId,
  required String url,
  required String title,
  required bool live,
  String? poster,
}) =>
    {
      'type': 'LOAD',
      'requestId': requestId,
      'autoplay': true,
      'currentTime': 0,
      'media': {
        'contentId': url,
        'contentType': castContentType(url),
        'streamType': live ? 'LIVE' : 'BUFFERED',
        'metadata': {
          'metadataType': 0,
          'title': title,
          if (poster != null && poster.isNotEmpty)
            'images': [
              {'url': poster}
            ],
        },
      },
    };

/// One open conversation with a device. A seam so the controller can be tested without a network.
abstract class CastLink {
  /// Connects and starts the receiver; completes when it is ready for media.
  Future<void> launch();
  void send(String namespace, Map<String, dynamic> payload);
  Stream<Map<String, dynamic>> get messages;
  Future<void> close();
}

class _RealLink implements CastLink {
  final CastDevice device;
  CastSession? _session;
  _RealLink(this.device);

  @override
  Future<void> launch() async {
    final session = await CastSessionManager()
        .startSession(device, const Duration(seconds: 8));
    _session = session;
    final ready =
        session.stateStream.firstWhere((s) => s == CastSessionState.connected);
    session.sendMessage(CastSession.kNamespaceReceiver,
        {'type': 'LAUNCH', 'appId': castAppId, 'requestId': 1});
    await ready.timeout(const Duration(seconds: 12));
  }

  @override
  void send(String namespace, Map<String, dynamic> payload) =>
      _session?.sendMessage(namespace, payload);

  @override
  Stream<Map<String, dynamic>> get messages =>
      _session?.messageStream ?? const Stream.empty();

  @override
  Future<void> close() async {
    final s = _session;
    _session = null;
    if (s != null) {
      await CastSessionManager().endSession(s.sessionId);
    }
  }
}

typedef CastSearch = Future<List<CastDevice>> Function();
typedef CastLinkFactory = CastLink Function(CastDevice device);

/// Finds devices and drives one cast at a time. A singleton, so a cast carries on when the player
/// screen closes and can be stopped from the next player.
class CastController extends ChangeNotifier {
  static final CastController instance = CastController();

  CastSearch search;
  CastLinkFactory link;
  CastController({CastSearch? search, CastLinkFactory? link})
      : search = search ??
            (() => CastDiscoveryService()
                .search(timeout: const Duration(seconds: 4))),
        link = link ?? _RealLink.new;

  List<CastDevice> devices = const [];
  bool scanning = false;
  CastDevice? device;
  String? title;
  String? error;
  bool connecting = false;
  bool paused = false;
  int? _mediaSessionId;
  int _req = 1;
  CastLink? _link;
  StreamSubscription<Map<String, dynamic>>? _sub;

  bool get casting => _link != null && device != null;

  Future<void> scan() async {
    if (scanning) return;
    scanning = true;
    error = null;
    notifyListeners();
    try {
      devices = await search();
    } catch (e) {
      error = 'Could not search the network: $e';
    }
    scanning = false;
    notifyListeners();
  }

  /// Starts [url] on [target], connecting first if this is a different device.
  Future<bool> play(CastDevice target,
      {required String url,
      required String title,
      required bool live,
      String? poster}) async {
    error = null;
    connecting = true;
    notifyListeners();
    try {
      if (_link == null || device != target) {
        await stop(notify: false);
        final l = link(target);
        _link = l;
        device = target;
        await l.launch();
        _sub = l.messages.listen(_onMessage, onError: (_) {}, onDone: () {
          if (_link == l) _reset();
        });
      }
      this.title = title;
      paused = false;
      _mediaSessionId = null;
      _link!.send(
          CastSession.kNamespaceMedia,
          castLoadMessage(
              requestId: ++_req,
              url: url,
              title: title,
              live: live,
              poster: poster));
      connecting = false;
      notifyListeners();
      return true;
    } catch (e) {
      error = 'Could not cast to ${target.name}. Is it on the same Wi-Fi?';
      connecting = false;
      await stop(notify: false);
      notifyListeners();
      return false;
    }
  }

  void _onMessage(Map<String, dynamic> m) {
    if (m['type'] == 'MEDIA_STATUS') {
      final st = m['status'];
      if (st is List && st.isNotEmpty) {
        final s = st.first as Map;
        _mediaSessionId = s['mediaSessionId'] as int? ?? _mediaSessionId;
        final state = s['playerState'];
        final nowPaused = state == 'PAUSED';
        if (nowPaused != paused) {
          paused = nowPaused;
          notifyListeners();
        }
        if (state == 'IDLE' && s['idleReason'] == 'ERROR') {
          error = 'The device could not play this stream.';
          notifyListeners();
        }
      }
    }
  }

  void togglePause() {
    final id = _mediaSessionId;
    if (_link == null || id == null) return;
    _link!.send(CastSession.kNamespaceMedia, {
      'type': paused ? 'PLAY' : 'PAUSE',
      'mediaSessionId': id,
      'requestId': ++_req
    });
  }

  void _reset() {
    _sub?.cancel();
    _sub = null;
    _link = null;
    device = null;
    title = null;
    paused = false;
    _mediaSessionId = null;
    notifyListeners();
  }

  Future<void> stop({bool notify = true}) async {
    final l = _link;
    _sub?.cancel();
    _sub = null;
    _link = null;
    device = null;
    title = null;
    paused = false;
    _mediaSessionId = null;
    if (l != null) {
      try {
        await l.close();
      } catch (_) {}
    }
    if (notify) notifyListeners();
  }
}
