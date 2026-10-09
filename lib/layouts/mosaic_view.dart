import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/media.dart';
import '../screens/open_item.dart';
import '../state/app_state.dart';
import '../widgets/live_preview.dart';
import '../widgets/tv.dart';
import 'bento_view.dart' show NowNext;
import 'cable_view.dart' show SoftKeys;
import 'common.dart';
import 'shell_nav.dart';
import 'ui_layout.dart';

/// Mosaic sits on mowed pitch stripes.
class MosaicBackdrop extends StatelessWidget {
  final Widget child;
  const MosaicBackdrop({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    const a = Color(0xFF14693A), b = Color(0xFF116132);
    const n = 8;
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [for (var i = 0; i < n; i++) ...(i.isEven ? const [a, a] : const [b, b])],
          stops: [for (var i = 0; i < n; i++) ...[i / n, (i + 1) / n]],
        ),
      ),
      child: child,
    );
  }
}

/// Mosaic's Home: four channel tiles with one holding the "audio" (the focused tile), a tray to
/// choose what fills it, and OK for full screen. Each tile plays its channel live, only the one with
/// the sound is audible (see [LivePreview]). Four streams at once is a lot for a small TV stick, so
/// the Live pictures setting turns them all off, and on a phone only the big tile plays.
class MosaicHome extends StatefulWidget {
  const MosaicHome({super.key});

  @override
  State<MosaicHome> createState() => _MosaicHomeState();
}

class _MosaicHomeState extends State<MosaicHome> {
  List<int>? _tiles; // indexes into the live list, -1 = empty
  int _audio = 0;

  List<int> _initial(List<MediaItem> live, AppState s) {
    final out = <int>[];
    for (final r in s.recents.where((e) => e.kind == MediaKind.live)) {
      final at = live.indexWhere((c) => c.key == r.key);
      if (at >= 0 && !out.contains(at)) out.add(at);
      if (out.length == 4) break;
    }
    for (var i = 0; i < live.length && out.length < 4; i++) {
      if (!out.contains(i)) out.add(i);
    }
    while (out.length < 4) {
      out.add(-1);
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final p = LayoutPalette.of(context);
    final tv = TvScope.of(context);
    final wide = tv || MediaQuery.sizeOf(context).width >= 800;
    final live = s.shown.live;
    if (live.isEmpty) {
      return Center(child: Text('No live channels in this source.', style: TextStyle(color: p.text)));
    }
    final tiles = _tiles ??= _initial(live, s);

    Widget tile(int t, {bool big = false}) => _Tile(
          channel: tiles[t] >= 0 && tiles[t] < live.length ? live[tiles[t]] : null,
          number: tiles[t] + 1,
          slot: t + 1,
          audio: _audio == t,
          big: big,
          live: wide || big,
          autofocus: tv && t == 0,
          onFocus: () {
            if (_audio != t) setState(() => _audio = t);
          },
          onTap: () {
            final ch = tiles[t] >= 0 && tiles[t] < live.length ? live[tiles[t]] : null;
            if (ch != null) openItem(context, ch, queue: live);
          },
        );

    if (!wide) {
      final others = [for (var t = 0; t < 4; t++) if (t != _audio) t];
      return Padding(
        padding: const EdgeInsets.all(10),
        child: Column(children: [
          Expanded(child: tile(_audio, big: true)),
          const SizedBox(height: 8),
          SizedBox(
            height: 110,
            child: Row(children: [
              for (final t in others)
                Expanded(
                  child: Padding(
                    padding: EdgeInsets.only(right: t == others.last ? 0 : 8),
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => setState(() => _audio = t),
                      child: AbsorbPointer(child: tile(t)),
                    ),
                  ),
                ),
            ]),
          ),
        ]),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 6),
      child: Column(children: [
        Expanded(
          child: Column(children: [
            Expanded(child: Row(children: [Expanded(child: tile(0)), const SizedBox(width: 8), Expanded(child: tile(1))])),
            const SizedBox(height: 8),
            Expanded(child: Row(children: [Expanded(child: tile(2)), const SizedBox(width: 8), Expanded(child: tile(3))])),
          ]),
        ),
        const SizedBox(height: 8),
        _Tray(
          live: live,
          slot: _audio + 1,
          current: tiles[_audio],
          onPick: (i) => setState(() => tiles[_audio] = i),
        ),
        const SizedBox(height: 8),
        SoftKeys(onSelect: (i) => ShellNav.maybeOf(context)?.select(i)),
      ]),
    );
  }
}

class _Tile extends StatelessWidget {
  final MediaItem? channel;
  final int number, slot;
  final bool audio, big, live, autofocus;
  final VoidCallback onFocus, onTap;
  const _Tile({
    required this.channel,
    required this.number,
    required this.slot,
    required this.audio,
    required this.big,
    required this.live,
    required this.autofocus,
    required this.onFocus,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final p = LayoutPalette.of(context);
    final small = !big && MediaQuery.sizeOf(context).width < 800 && !TvScope.of(context);
    return FocusSurface(
      radius: 8,
      autofocus: autofocus,
      semanticLabel: channel == null ? 'Empty tile $slot' : '${channel!.name}${audio ? ', has the sound' : ''}',
      onFocus: (f) {
        if (f) onFocus();
      },
      onTap: onTap,
      builder: (_, __) {
        const bg = DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
                begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFF0D3A20), Color(0xFF0B1F4D)]),
          ),
        );
        final playing = channel != null && live;
        return Container(
          width: double.infinity,
          height: double.infinity,
          decoration: BoxDecoration(border: Border.all(color: audio ? p.accent : p.line, width: audio ? 4 : 1)),
          child: Stack(fit: StackFit.expand, children: [
            if (playing)
              LivePreview(key: ValueKey(channel!.key), channel: channel!, sound: audio, fallback: bg)
            else
              bg,
            // Keeps the number, name and what is on readable over a moving picture.
            if (playing)
              const IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Color(0xAA000000), Color(0x00000000), Color(0x00000000), Color(0xAA000000)],
                      stops: [0.0, 0.3, 0.7, 1.0],
                    ),
                  ),
                ),
              ),
            Padding(
              padding: EdgeInsets.all(small ? 8 : 14),
              child: channel == null
                  ? Center(child: Text('Empty', style: TextStyle(color: p.muted, fontSize: small ? 13 : 18)))
                  : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(children: [
                        Text('$number',
                            style: TextStyle(
                                color: p.accent, fontSize: small ? 22 : (big ? 44 : 34), fontWeight: FontWeight.w900, height: 1)),
                        const SizedBox(width: 10),
                        Expanded(
                            child: Text(channel!.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                    color: p.text, fontSize: small ? 13 : (big ? 26 : 20), fontWeight: FontWeight.w800))),
                        Icon(audio ? Icons.volume_up : Icons.volume_off,
                            color: audio ? p.accent : p.muted, size: small ? 16 : 24),
                      ]),
                      const Spacer(),
                      if (!small)
                        NowNext(
                          channel: channel!,
                          builder: (now, _) => Text(now?.title ?? 'Live',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(color: p.text, fontSize: big ? 20 : 16, fontWeight: FontWeight.w600)),
                        ),
                    ]),
            ),
          ]),
        );
      },
    );
  }
}

/// Channels to put in the tile that has the sound.
class _Tray extends StatelessWidget {
  final List<MediaItem> live;
  final int slot, current;
  final ValueChanged<int> onPick;
  const _Tray({required this.live, required this.slot, required this.current, required this.onPick});

  @override
  Widget build(BuildContext context) {
    final p = LayoutPalette.of(context);
    return SizedBox(
      height: 54,
      child: Row(children: [
        Padding(
          padding: const EdgeInsets.only(right: 12),
          child: Text('TILE $slot', style: TextStyle(color: p.accent, fontWeight: FontWeight.w900, letterSpacing: 1.6, fontSize: 16)),
        ),
        Expanded(
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: live.length,
            separatorBuilder: (_, __) => const SizedBox(width: 6),
            itemBuilder: (_, i) => FocusSurface(
              radius: 4,
              semanticLabel: 'Put ${live[i].name} in tile $slot',
              onTap: () => onPick(i),
              builder: (_, __) => Container(
                alignment: Alignment.center,
                padding: const EdgeInsets.symmetric(horizontal: 14),
                color: i == current ? p.accent : p.surface,
                child: Text('${i + 1}  ${live[i].name}',
                    style: TextStyle(color: i == current ? p.onAccent : p.text, fontWeight: FontWeight.w700, fontSize: 15)),
              ),
            ),
          ),
        ),
      ]),
    );
  }
}
