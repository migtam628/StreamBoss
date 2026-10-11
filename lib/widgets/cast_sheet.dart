import 'package:cast/cast.dart';
import 'package:flutter/material.dart';
import '../services/cast_service.dart';
import '../theme.dart';
import '../l10n/l10n.dart';

/// "Cast to TV (experimental)": lists Chromecast devices on the network and plays [url] on the one
/// picked. [onStarted] runs after a cast starts (the player pauses its own picture).
Future<void> showCastSheet(
  BuildContext context, {
  required String url,
  required String title,
  required bool live,
  String? poster,
  VoidCallback? onStarted,
  CastController? controller,
}) {
  final c = controller ?? CastController.instance;
  c.scan();
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: Boss.surface,
    isScrollControlled: true,
    builder: (ctx) => CastSheet(
        controller: c,
        url: url,
        title: title,
        live: live,
        poster: poster,
        onStarted: onStarted),
  );
}

class CastSheet extends StatelessWidget {
  final CastController controller;
  final String url, title;
  final bool live;
  final String? poster;
  final VoidCallback? onStarted;
  const CastSheet({
    super.key,
    required this.controller,
    required this.url,
    required this.title,
    required this.live,
    this.poster,
    this.onStarted,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: ListenableBuilder(
        listenable: controller,
        builder: (context, _) {
          final c = controller;
          return ConstrainedBox(
            constraints: BoxConstraints(
                maxHeight: MediaQuery.sizeOf(context).height * 0.8),
            child: ListView(
                shrinkWrap: true,
                padding: const EdgeInsets.fromLTRB(8, 16, 8, 16),
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Row(children: [
                      Expanded(
                          child: Text(tr('Cast to TV'),
                              style: const TextStyle(
                                  fontSize: 20, fontWeight: FontWeight.w800))),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                            border: Border.all(color: Boss.accent),
                            borderRadius: BorderRadius.circular(6)),
                        child: Text(tr('EXPERIMENTAL'),
                            style: const TextStyle(
                                fontSize: 11, fontWeight: FontWeight.w800)),
                      ),
                    ]),
                  ),
                  if (c.casting)
                    ListTile(
                      leading: const Icon(Icons.cast_connected),
                      title: Text(trf('Casting to {name}', {'name': c.device!.name})),
                      subtitle: Text(c.title ?? ''),
                      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                        IconButton(
                            tooltip: c.paused ? tr('Resume') : tr('Pause'),
                            icon:
                                Icon(c.paused ? Icons.play_arrow : Icons.pause),
                            onPressed: c.togglePause),
                        IconButton(
                            tooltip: tr('Stop casting'),
                            icon: const Icon(Icons.stop_circle_outlined),
                            onPressed: c.stop),
                      ]),
                    ),
                  if (c.error != null)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                      child: Text(c.error!,
                          style: const TextStyle(color: Colors.redAccent)),
                    ),
                  if (c.scanning || c.connecting)
                    ListTile(
                      leading: const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(strokeWidth: 2.5)),
                      title: Text(c.connecting
                          ? 'Connecting...'
                          : tr('Looking for devices...')),
                    ),
                  for (final CastDevice d in c.devices)
                    ListTile(
                      leading: const Icon(Icons.cast),
                      title: Text(d.name),
                      subtitle: Text(d.host),
                      selected: c.device == d,
                      onTap: c.connecting
                          ? null
                          : () async {
                              final ok = await c.play(d,
                                  url: url,
                                  title: title,
                                  live: live,
                                  poster: poster);
                              if (ok) onStarted?.call();
                            },
                    ),
                  if (!c.scanning && c.devices.isEmpty && c.error == null)
                    ListTile(
                      leading: const Icon(Icons.info_outline),
                      title: Text(tr('No devices found')),
                      subtitle: Text(
                          tr('Put this device and the TV on the same Wi-Fi, then search again.')),
                    ),
                  ListTile(
                      leading: const Icon(Icons.refresh),
                      title: Text(tr('Search again')),
                      onTap: c.scanning ? null : c.scan),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
                    child: Text(
                        tr('Works with Chromecast and TVs with Chromecast built in. The TV opens the stream itself, so a '
                        'provider that allows one connection at a time will count two. Streams a Chromecast cannot play '
                        '(some codecs, or a provider that checks the device) will fail. For AirPlay, use Screen Mirroring '
                        'from the system menu.'),
                        style: const TextStyle(fontSize: 13, color: Colors.white60)),
                  ),
                ]),
          );
        },
      ),
    );
  }
}
