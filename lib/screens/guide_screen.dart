import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/mini_player.dart';
import '../widgets/channel_filter_bar.dart';
import '../widgets/live_preview.dart';
import '../widgets/net_image.dart';
import '../models/media.dart';
import '../services/xmltv.dart';
import '../services/xtream_client.dart';
import '../services/time_format.dart';
import '../state/app_state.dart';
import '../state/settings_state.dart';
import '../layouts/ui_layout.dart';
import '../widgets/focus_card.dart';
import '../widgets/programme_sheet.dart';
import 'open_item.dart';

enum _Mode { grid, list }

/// TV guide: an XMLTV time grid when the source provides one, plus a simpler
/// now/next list (Xtream short EPG) that also works without XMLTV.
class GuideScreen extends StatefulWidget {
  /// Called when focus lands on a programme cell (used by Prime Time's details header).
  final void Function(MediaItem channel, Programme programme)? onFocusProgramme;
  const GuideScreen({super.key, this.onFocusProgramme});

  @override
  State<GuideScreen> createState() => _GuideScreenState();
}

class _GuideScreenState extends State<GuideScreen> {
  String? _cat;
  _Mode _mode = _Mode.grid;
  bool _requested = false;

  // The channel shown in the preview, and the programme the cursor is on (if any).
  MediaItem? _sel;
  Programme? _selProg;

  /// A tap on a channel or a programme that is on now: the first tap puts the channel in the preview,
  /// and a tap on the one already there is left for the caller to open. A remote's focus does the first
  /// part by itself, so OK there opens straight away.
  bool _pick(MediaItem ch, Programme? p) {
    if (widget.onFocusProgramme != null) return false; // Prime Time shows its own header
    if (_sel?.key == ch.key) return false;
    setState(() {
      _sel = ch;
      _selProg = p;
    });
    return true;
  }

  void _focused(MediaItem ch, Programme p) {
    if (_sel?.key != ch.key || _selProg != p) {
      setState(() {
        _sel = ch;
        _selProg = p;
      });
    }
    widget.onFocusProgramme?.call(ch, p);
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    context.watch<SettingsState>(); // rebuild when the clock format changes
    if (!_requested) {
      _requested = true;
      WidgetsBinding.instance.addPostFrameCallback((_) => s.loadGuide());
    }
    final all = s.shown.live;
    if (all.isEmpty) {
      return Center(child: Text('No live channels.', style: TextStyle(color: LayoutPalette.of(context).muted)));
    }
    final filtered = s.filterChannels(all);
    final items = _cat == null ? filtered : filtered.where((i) => i.categoryId == _cat).toList();
    final showGrid = _mode == _Mode.grid && s.hasGuideSource;
    // Keep the preview on a channel that is still in the list.
    final sel = items.isEmpty ? null : (items.any((c) => c.key == _sel?.key) ? _sel : items.first);

    return Column(children: [
      if (widget.onFocusProgramme == null && sel != null)
        _GuidePreview(
          key: const ValueKey('guide-preview'),
          channel: sel,
          programme: _selProg != null && _sel?.key == sel.key ? _selProg : null,
          queue: items,
        ),
      ChannelFilterBar(shown: items.length),
      Row(children: [
        Expanded(
          child: SizedBox(
            height: 56,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              children: [
                for (final c in [const Category('', 'All'), ...s.shown.liveCategories])
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(c.name),
                      selected: (_cat ?? '') == c.id,
                      selectedColor: LayoutPalette.of(context).accent,
                      onSelected: (_) => setState(() => _cat = c.id.isEmpty ? null : c.id),
                    ),
                  ),
              ],
            ),
          ),
        ),
        if (s.hasGuideSource)
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: SegmentedButton<_Mode>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(value: _Mode.grid, icon: Icon(Icons.grid_view, size: 18)),
                ButtonSegment(value: _Mode.list, icon: Icon(Icons.view_list, size: 18)),
              ],
              selected: {_mode},
              onSelectionChanged: (v) => setState(() => _mode = v.first),
            ),
          ),
      ]),
      Expanded(
        child: showGrid
            ? (s.guideLoading
                ? const Center(
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                    CircularProgressIndicator(),
                    SizedBox(height: 12),
                    Text('Loading guide…'),
                  ]))
                : s.guideError != null
                    ? Center(
                        child: Column(mainAxisSize: MainAxisSize.min, children: [
                        Text('Guide failed: ${s.guideError}',
                            style: TextStyle(color: LayoutPalette.of(context).accent)),
                        TextButton(
                            onPressed: () => s.loadGuide(force: true),
                            child: const Text('Retry')),
                      ]))
                    : GuideGrid(channels: items, onFocusProgramme: _focused, onPick: _pick))
            : _NowNextList(items: items, onPick: _pick),
      ),
    ]);
  }
}

/// Time grid. Names stay fixed on the left; programme cells scroll with a
/// shared horizontal controller driven by the time header (or by dragging /
/// D-pad focus on a cell).
class GuideGrid extends StatefulWidget {
  final List<MediaItem> channels;
  final void Function(MediaItem channel, Programme programme)? onFocusProgramme;

  /// Called first on a tap; true means it was used (to preview) and nothing is opened.
  final bool Function(MediaItem channel, Programme? programme)? onPick;
  const GuideGrid({super.key, required this.channels, this.onFocusProgramme, this.onPick});

  @override
  State<GuideGrid> createState() => _GuideGridState();
}

class _GuideGridState extends State<GuideGrid> {
  static const nameW = 140.0;
  static const rowH = 60.0;
  static const pxPerMin = 4.0;
  static const windowMin = 8 * 60;

  final _h = ScrollController();
  late final DateTime _start = _floor30(DateTime.now().subtract(const Duration(minutes: 30)));

  static DateTime _floor30(DateTime d) =>
      DateTime(d.year, d.month, d.day, d.hour, d.minute >= 30 ? 30 : 0);

  double _x(DateTime t) => t.difference(_start).inSeconds / 60 * pxPerMin;

  @override
  void dispose() {
    _h.dispose();
    super.dispose();
  }

  void _reveal(double left, double width) {
    if (!_h.hasClients) return;
    final off = _h.offset;
    final view = _h.position.viewportDimension;
    if (left < off || left + width > off + view) {
      _h.animateTo(
        (left - 16).clamp(0.0, _h.position.maxScrollExtent),
        duration: const Duration(milliseconds: 150),
        curve: Curves.easeOut,
      );
    }
  }

  String _hm(DateTime d) => fmtTime(d, use24h: context.read<SettingsState>().use24h);

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    const totalW = windowMin * pxPerMin;
    return Column(children: [
      SizedBox(
        height: 32,
        child: Row(children: [
          const SizedBox(width: nameW),
          Expanded(
            child: SingleChildScrollView(
              controller: _h,
              scrollDirection: Axis.horizontal,
              child: SizedBox(
                width: totalW,
                child: Stack(children: [
                  for (var m = 0; m < windowMin; m += 30)
                    Positioned(
                      left: m * pxPerMin + 6,
                      top: 8,
                      child: Text(_hm(_start.add(Duration(minutes: m))),
                          style: TextStyle(color: LayoutPalette.of(context).muted, fontSize: 12)),
                    ),
                ]),
              ),
            ),
          ),
        ]),
      ),
      Expanded(
        child: ListView.builder(
          itemExtent: rowH,
          itemCount: widget.channels.length,
          itemBuilder: (_, i) {
            final ch = widget.channels[i];
            final progs = s.programmesFor(ch);
            return Row(children: [
              SizedBox(
                width: nameW,
                child: InkWell(
                  onTap: () {
                    if (widget.onPick?.call(ch, null) ?? false) return;
                    openItem(context, ch, queue: widget.channels);
                  },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(ch.name,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                    ),
                  ),
                ),
              ),
              Expanded(
                child: GestureDetector(
                  onHorizontalDragUpdate: (d) {
                    if (_h.hasClients) {
                      _h.jumpTo((_h.offset - d.delta.dx).clamp(0.0, _h.position.maxScrollExtent));
                    }
                  },
                  child: ClipRect(
                    child: AnimatedBuilder(
                      animation: _h,
                      builder: (_, __) {
                        final off = _h.hasClients ? _h.offset : 0.0;
                        if (progs.isEmpty) {
                          return Align(
                            alignment: Alignment.centerLeft,
                            child: Padding(
                              padding: const EdgeInsets.only(left: 8),
                              child: Text('No guide data', style: TextStyle(color: LayoutPalette.of(context).muted)),
                            ),
                          );
                        }
                        return Stack(children: [
                          for (final p in progs)
                            if (_x(p.end) > 0 && _x(p.start) < totalW)
                              _cell(ch, p, off),
                        ]);
                      },
                    ),
                  ),
                ),
              ),
            ]);
          },
        ),
      ),
    ]);
  }

  Widget _cell(MediaItem ch, Programme p, double off) {
    final left = _x(p.start).clamp(0.0, windowMin * pxPerMin);
    final right = _x(p.end).clamp(0.0, windowMin * pxPerMin);
    final width = (right - left - 3).clamp(8.0, windowMin * pxPerMin);
    return Positioned(
      left: left - off,
      width: width,
      top: 4,
      bottom: 4,
      child: FocusCard(
        radius: 8,
        onFocus: (f) {
          if (f) {
            _reveal(left, width);
            widget.onFocusProgramme?.call(ch, p);
          }
        },
        // The programme on now opens the channel; any other one shows what it is (and its catch-up).
        onTap: () {
          if (p.isNow) {
            if (widget.onPick?.call(ch, p) ?? false) return;
            openItem(context, ch, queue: widget.channels);
          } else {
            showProgrammeSheet(context, ch, p, queue: widget.channels);
          }
        },
        onLongPress: () => showProgrammeSheet(context, ch, p, queue: widget.channels),
        child: Container(
          color: p.isNow ? LayoutPalette.of(context).accent.withValues(alpha: 0.35) : LayoutPalette.of(context).surfaceHi,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(p.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
            Text('${_hm(p.start)}–${_hm(p.end)}',
                maxLines: 1,
                overflow: TextOverflow.clip,
                style: TextStyle(fontSize: 10, color: LayoutPalette.of(context).muted)),
          ]),
        ),
      ),
    );
  }
}

/// Lazy now/next per visible row via Xtream short EPG.
class _NowNextList extends StatefulWidget {
  final List<MediaItem> items;
  final bool Function(MediaItem channel, Programme? programme)? onPick;
  const _NowNextList({required this.items, this.onPick});

  @override
  State<_NowNextList> createState() => _NowNextListState();
}

class _NowNextListState extends State<_NowNextList> {
  final _cache = <String, Future<List<EpgEntry>>>{};

  String _hm(DateTime d) => fmtTime(d, use24h: context.read<SettingsState>().use24h);

  @override
  Widget build(BuildContext context) {
    final s = context.read<AppState>();
    return ListView.builder(
      itemCount: widget.items.length,
      itemBuilder: (_, i) {
        final ch = widget.items[i];
        final fut = _cache.putIfAbsent(ch.id, () => s.epg(ch).catchError((_) => <EpgEntry>[]));
        return ListTile(
          leading: Icon(Icons.live_tv, color: LayoutPalette.of(context).muted),
          title: Text(ch.name, maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: FutureBuilder<List<EpgEntry>>(
            future: fut,
            builder: (_, snap) {
              final list = snap.data ?? const [];
              final now = list.where((e) => e.isNow).firstOrNull;
              final next = list.where((e) => e.start.isAfter(DateTime.now())).firstOrNull;
              if (now == null) {
                return Text(snap.connectionState == ConnectionState.done ? 'No guide data' : '…',
                    style: TextStyle(color: LayoutPalette.of(context).muted));
              }
              return Text(
                '${_hm(now.start)}–${_hm(now.end)}  ${now.title}'
                '${next != null ? '\nNext ${_hm(next.start)}  ${next.title}' : ''}',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              );
            },
          ),
          onTap: () {
            if (widget.onPick?.call(ch, null) ?? false) return;
            openItem(context, ch, queue: widget.items);
          },
        );
      },
    );
  }
}

/// The picture of the channel selected in the guide, playing a moment after it is chosen, with what is
/// on and buttons to watch it full screen or in the mini player.
class _GuidePreview extends StatelessWidget {
  final MediaItem channel;
  final Programme? programme;
  final List<MediaItem> queue;
  const _GuidePreview({super.key, required this.channel, required this.programme, required this.queue});

  @override
  Widget build(BuildContext context) {
    final p = LayoutPalette.of(context);
    final s = context.watch<AppState>();
    final use24h = context.select<SettingsState, bool>((st) => st.use24h);
    final progs = s.programmesFor(channel);
    final now = progs.where((x) => x.isNow).firstOrNull;
    final shown = programme ?? now;
    final next = progs.where((x) => x.start.isAfter(DateTime.now())).firstOrNull;
    final wide = MediaQuery.sizeOf(context).width >= 700;
    final w = wide ? 220.0 : 128.0;
    String hm(DateTime d) => fmtTime(d, use24h: use24h);

    Widget action(IconData icon, String label, VoidCallback onTap, {bool primary = false}) => FocusCard(
          radius: 20,
          onTap: onTap,
          child: Container(
            padding: EdgeInsets.symmetric(horizontal: wide ? 14 : 10, vertical: wide ? 9 : 7),
            color: primary ? p.accent : p.wash(0.1),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(icon, size: 18, color: primary ? p.onAccent : p.text),
              if (wide) ...[
                const SizedBox(width: 6),
                Text(label, style: TextStyle(fontWeight: FontWeight.w700, color: primary ? p.onAccent : p.text)),
              ],
            ]),
          ),
        );

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 4, 12, 4),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(color: p.surface, borderRadius: BorderRadius.circular(14), border: Border.all(color: p.line)),
      child: Row(children: [
        SizedBox(
          width: w,
          child: AspectRatio(
            aspectRatio: 16 / 9,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: Stack(fit: StackFit.expand, children: [
                Container(color: p.surfaceHi),
                LivePreview(
                  key: ValueKey(channel.key),
                  channel: channel,
                  fallback: channel.poster == null || channel.poster!.isEmpty
                      ? const SizedBox.shrink()
                      : Padding(
                          padding: const EdgeInsets.all(12),
                          child: NetImage(channel.poster!, fit: BoxFit.contain, fallback: () => const SizedBox.shrink()),
                        ),
                ),
                Positioned(
                  left: 6,
                  top: 6,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                    decoration: BoxDecoration(color: const Color(0xFFE5484D), borderRadius: BorderRadius.circular(4)),
                    child: const Text('LIVE', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 10, letterSpacing: 1)),
                  ),
                ),
              ]),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            Text(channel.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: p.muted, fontSize: 13, fontWeight: FontWeight.w700)),
            Text(shown?.title ?? 'No guide data',
                maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: wide ? 22 : 17, fontWeight: FontWeight.w800)),
            if (shown != null)
              Text('${hm(shown.start)} – ${hm(shown.end)}${next != null && shown == now ? '   Next ${hm(next.start)} ${next.title}' : ''}',
                  maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: p.muted, fontSize: 13)),
            const SizedBox(height: 6),
            Wrap(spacing: 8, runSpacing: 6, children: [
              action(Icons.play_arrow, 'Watch', () => openItem(context, channel, queue: queue), primary: true),
              action(Icons.picture_in_picture, 'Mini player', () async {
                final ok = await MiniPlayer.instance.playChannel(context.read<SettingsState>(), channel, queue: queue);
                if (!ok && context.mounted) {
                  ScaffoldMessenger.maybeOf(context)?.showSnackBar(const SnackBar(content: Text('Could not start the mini player.')));
                }
              }),
            ]),
          ]),
        ),
      ]),
    );
  }
}
