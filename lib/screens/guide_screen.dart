import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/media.dart';
import '../services/xmltv.dart';
import '../services/xtream_client.dart';
import '../services/time_format.dart';
import '../state/app_state.dart';
import '../state/settings_state.dart';
import '../theme.dart';
import '../widgets/focus_card.dart';
import 'open_item.dart';

enum _Mode { grid, list }

/// TV guide: an XMLTV time grid when the source provides one, plus a simpler
/// now/next list (Xtream short EPG) that also works without XMLTV.
class GuideScreen extends StatefulWidget {
  const GuideScreen({super.key});

  @override
  State<GuideScreen> createState() => _GuideScreenState();
}

class _GuideScreenState extends State<GuideScreen> {
  String? _cat;
  _Mode _mode = _Mode.grid;
  bool _requested = false;

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
      return const Center(child: Text('No live channels.', style: TextStyle(color: Boss.muted)));
    }
    final items = _cat == null ? all : all.where((i) => i.categoryId == _cat).toList();
    final showGrid = _mode == _Mode.grid && s.hasGuideSource;

    return Column(children: [
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
                      selectedColor: Boss.accent,
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
                            style: const TextStyle(color: Boss.accent)),
                        TextButton(
                            onPressed: () => s.loadGuide(force: true),
                            child: const Text('Retry')),
                      ]))
                    : GuideGrid(channels: items))
            : _NowNextList(items: items),
      ),
    ]);
  }
}

/// Time grid. Names stay fixed on the left; programme cells scroll with a
/// shared horizontal controller driven by the time header (or by dragging /
/// D-pad focus on a cell).
class GuideGrid extends StatefulWidget {
  final List<MediaItem> channels;
  const GuideGrid({super.key, required this.channels});

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
                          style: const TextStyle(color: Boss.muted, fontSize: 12)),
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
                  onTap: () => openItem(context, ch, queue: widget.channels),
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
                          return const Align(
                            alignment: Alignment.centerLeft,
                            child: Padding(
                              padding: EdgeInsets.only(left: 8),
                              child: Text('No guide data', style: TextStyle(color: Boss.muted)),
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
          if (f) _reveal(left, width);
        },
        onTap: () => openItem(context, ch, queue: widget.channels),
        child: Container(
          color: p.isNow ? Boss.accent.withValues(alpha: 0.35) : Boss.surfaceHi,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(p.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
            Text('${_hm(p.start)}–${_hm(p.end)}',
                maxLines: 1,
                overflow: TextOverflow.clip,
                style: const TextStyle(fontSize: 10, color: Boss.muted)),
          ]),
        ),
      ),
    );
  }
}

/// Lazy now/next per visible row via Xtream short EPG.
class _NowNextList extends StatefulWidget {
  final List<MediaItem> items;
  const _NowNextList({required this.items});

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
          leading: const Icon(Icons.live_tv, color: Boss.muted),
          title: Text(ch.name, maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: FutureBuilder<List<EpgEntry>>(
            future: fut,
            builder: (_, snap) {
              final list = snap.data ?? const [];
              final now = list.where((e) => e.isNow).firstOrNull;
              final next = list.where((e) => e.start.isAfter(DateTime.now())).firstOrNull;
              if (now == null) {
                return Text(snap.connectionState == ConnectionState.done ? 'No guide data' : '…',
                    style: const TextStyle(color: Boss.muted));
              }
              return Text(
                '${_hm(now.start)}–${_hm(now.end)}  ${now.title}'
                '${next != null ? '\nNext ${_hm(next.start)}  ${next.title}' : ''}',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              );
            },
          ),
          onTap: () => openItem(context, ch, queue: widget.items),
        );
      },
    );
  }
}
