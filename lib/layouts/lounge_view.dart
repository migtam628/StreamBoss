import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/media.dart';
import '../screens/open_item.dart';
import '../services/time_format.dart';
import '../services/xtream_client.dart';
import '../state/app_state.dart';
import '../state/settings_state.dart';
import '../widgets/channel_filter_bar.dart';
import '../widgets/live_preview.dart';
import '../widgets/net_image.dart';
import '../widgets/tv.dart';
import 'common.dart';
import 'ui_layout.dart';
import '../widgets/channel_sheet.dart';

/// Lounge's Home: the channel you were on, playing live and muted in the top half, and a strip of
/// channels under it. Moving along the strip changes the picture (after a short pause, so flicking
/// does not open every stream); OK, or a second tap, plays full screen.
class LoungeHome extends StatefulWidget {
  const LoungeHome({super.key});

  @override
  State<LoungeHome> createState() => _LoungeHomeState();
}

class _LoungeHomeState extends State<LoungeHome> {
  String? _cat;
  int? _idx;
  final _epg = <String, Future<List<EpgEntry>>>{};

  Future<List<EpgEntry>> _epgFor(MediaItem ch) => _epg.putIfAbsent(ch.id,
      () => context.read<AppState>().epg(ch).catchError((_) => <EpgEntry>[]));

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final p = LayoutPalette.of(context);
    final tv = TvScope.of(context);
    final wide = tv || MediaQuery.sizeOf(context).width >= 800;
    final use24h = context.select<SettingsState, bool>((st) => st.use24h);
    final cats = s.shown.liveCategories;
    final all = s.shown.live;
    if (all.isEmpty) {
      return Center(
          child: Text('No live channels in this source.',
              style: TextStyle(color: p.muted)));
    }
    final base =
        _cat == null ? all : all.where((c) => c.categoryId == _cat).toList();
    final list = s.filterChannels(base);

    _idx ??= () {
      final last = s.recents.where((e) => e.kind == MediaKind.live).firstOrNull;
      final at = last == null ? -1 : list.indexWhere((c) => c.key == last.key);
      return at < 0 ? 0 : at;
    }();
    final idx = list.isEmpty ? 0 : _idx!.clamp(0, list.length - 1).toInt();
    final cur = list.isEmpty ? null : list[idx];

    void open() {
      if (cur != null) openItem(context, cur, queue: list);
    }

    final picture = ClipRRect(
      borderRadius: BorderRadius.circular(wide ? 18 : 14),
      child: FocusSurface(
        radius: wide ? 18 : 14,
        semanticLabel: cur == null ? 'No channel' : 'Watch ${cur.name}',
        onTap: open,
        builder: (_, __) => Stack(fit: StackFit.expand, children: [
          if (cur != null)
            // One preview for the whole strip: changing channel reuses its player, which is lighter than
            // starting a new one for every channel flicked past.
            LivePreview(
              channel: cur,
              fallback: ColoredBox(
                color: p.surfaceHi,
                child: Center(
                    child: Icon(Icons.play_circle_outline,
                        size: wide ? 96 : 64, color: p.muted)),
              ),
            ),
          const IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0x00000000), Color(0xB3000000)],
                  stops: [0.45, 1.0],
                ),
              ),
            ),
          ),
          Positioned(
            left: wide ? 28 : 16,
            right: wide ? 28 : 16,
            bottom: wide ? 22 : 12,
            child: cur == null
                ? const SizedBox.shrink()
                : _Info(
                    channel: cur,
                    number: idx + 1,
                    epg: _epgFor(cur),
                    use24h: use24h,
                    wide: wide),
          ),
        ]),
      ),
    );

    Widget tile(int i) {
      final c = list[i];
      final on = i == idx;
      return SizedBox(
        width: wide ? 190 : 140,
        child: FocusSurface(
          radius: 12,
          semanticLabel: '${i + 1} ${c.name}',
          // Focusing a tile on a TV selects it, so the picture follows the remote.
          onFocus: (f) {
            if (f && tv && _idx != i) setState(() => _idx = i);
          },
          onLongPress: () => itemMenu(context, c),
          onTap: () {
            if (i == idx) {
              open();
            } else {
              setState(() => _idx = i);
            }
          },
          builder: (_, __) => Container(
            color: on ? p.accent : p.surface,
            padding: const EdgeInsets.all(10),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(
                child: Row(children: [
                  Text('${i + 1}',
                      style: TextStyle(
                          fontSize: wide ? 20 : 16,
                          fontWeight: FontWeight.w800,
                          color: on ? p.bg : p.accent)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: c.poster == null
                        ? const SizedBox.shrink()
                        : NetImage(c.poster!,
                            fit: BoxFit.contain,
                            fallback: () => const SizedBox.shrink()),
                  ),
                ]),
              ),
              Text(c.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: wide ? 16 : 14,
                      fontWeight: FontWeight.w700,
                      color: on ? p.bg : p.text)),
            ]),
          ),
        ),
      );
    }

    final strip = SizedBox(
      height: wide ? 96 : 84,
      child: list.isEmpty
          ? Center(
              child: Text('No channels match the filter.',
                  style: TextStyle(color: p.muted)))
          : ListView.separated(
              scrollDirection: Axis.horizontal,
              padding:
                  EdgeInsets.symmetric(horizontal: wide ? 24 : 12, vertical: 6),
              itemCount: list.length,
              separatorBuilder: (_, __) => const SizedBox(width: 10),
              itemBuilder: (_, i) => tile(i),
            ),
    );

    return Column(children: [
      Expanded(
        child: Padding(
          padding: EdgeInsets.fromLTRB(
              wide ? 24 : 12, wide ? 16 : 8, wide ? 24 : 12, 6),
          child: picture,
        ),
      ),
      ChannelFilterBar(shown: list.length),
      ChipRow(
        labels: ['All', for (final c in cats) c.name],
        selected: _cat == null ? 0 : cats.indexWhere((c) => c.id == _cat) + 1,
        onSelect: (i) => setState(() {
          _cat = i == 0 ? null : cats[i - 1].id;
          _idx = 0;
        }),
      ),
      strip,
      const SizedBox(height: 8),
    ]);
  }
}

/// Number, name and what is on now, over the picture.
class _Info extends StatelessWidget {
  final MediaItem channel;
  final int number;
  final Future<List<EpgEntry>> epg;
  final bool use24h, wide;
  const _Info(
      {required this.channel,
      required this.number,
      required this.epg,
      required this.use24h,
      required this.wide});

  @override
  Widget build(BuildContext context) {
    final p = LayoutPalette.of(context);
    return Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
      Text('$number',
          style: TextStyle(
              fontSize: wide ? 64 : 40,
              height: 1,
              fontWeight: FontWeight.w800,
              color: p.accent)),
      SizedBox(width: wide ? 18 : 12),
      Expanded(
        child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(channel.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: wide ? 30 : 20,
                      fontWeight: FontWeight.w800,
                      color: Colors.white)),
              FutureBuilder<List<EpgEntry>>(
                future: epg,
                builder: (_, snap) {
                  final now = (snap.data ?? const <EpgEntry>[])
                      .where((e) => e.isNow)
                      .firstOrNull;
                  return Text(
                      now == null
                          ? 'Press OK to watch'
                          : 'Now: ${now.title}  ·  until ${fmtTime(now.end, use24h: use24h)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: wide ? 18 : 14,
                          color: Colors.white.withValues(alpha: 0.85)));
                },
              ),
            ]),
      ),
    ]);
  }
}
