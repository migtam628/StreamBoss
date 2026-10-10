import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/media.dart';
import '../screens/open_item.dart';
import '../services/time_format.dart';
import '../services/tonight.dart';
import '../state/app_state.dart';
import '../state/settings_state.dart';
import '../widgets/net_image.dart';
import '../widgets/programme_sheet.dart';
import '../widgets/tv.dart';
import 'common.dart';
import 'ui_layout.dart';

const _ink = Color(0xFF241D14);
const _paper = Color(0xFFF1E8D4);

const _weekdays = [
  'Monday',
  'Tuesday',
  'Wednesday',
  'Thursday',
  'Friday',
  'Saturday',
  'Sunday'
];
const _months = [
  'January',
  'February',
  'March',
  'April',
  'May',
  'June',
  'July',
  'August',
  'September',
  'October',
  'November',
  'December'
];

String _dateLine(DateTime d) =>
    '${_weekdays[d.weekday - 1]} ${d.day} ${_months[d.month - 1]}';

/// Tonight's Home: one timeline for the rest of the evening (what is on now, what starts later, what you
/// are partway through, what you saved), with the details of the highlighted line beside it.
class TonightHome extends StatefulWidget {
  const TonightHome({super.key});

  @override
  State<TonightHome> createState() => _TonightHomeState();
}

class _TonightHomeState extends State<TonightHome> {
  TonightDay _day = TonightDay.tonight;
  int _sel = 0;
  Timer? _tick;
  String _cacheKey = '';
  List<TonightEntry> _entries = const [];

  @override
  void initState() {
    super.initState();
    // Keeps "now" honest while the screen stays open.
    _tick = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() {});
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<AppState>().loadGuide();
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  List<TonightEntry> _build(AppState s) {
    final now = DateTime.now();
    final key =
        '${identityHashCode(s.guide)}|${_day.name}|${s.recents.length}|${s.favoriteItems.length}|${s.shown.live.length}|'
        '${now.year}${now.month}${now.day}${now.hour}${now.minute}';
    if (key != _cacheKey) {
      _cacheKey = key;
      _entries = buildTonight(
        now: now,
        day: _day,
        channels: s.shown.live,
        favorites: s.favoriteItems,
        recents: s.recents,
        programmesFor: s.programmesFor,
        canCatchUp: (c, p) => s.catchUpFor(c, p),
        resumeFor: s.resumeFor,
      );
    }
    return _entries;
  }

  void _open(TonightEntry e, AppState s) {
    final p = e.programme;
    if (p == null) {
      openItem(context, e.item);
    } else if (e.kind == TonightKind.live) {
      openItem(context, e.item, queue: s.shown.live);
    } else {
      showProgrammeSheet(context, e.item, p, queue: s.shown.live);
    }
  }

  String _tag(TonightEntry e) => switch (e.kind) {
        TonightKind.live => 'LIVE',
        TonightKind.upcoming =>
          _day == TonightDay.tomorrow ? 'TOMORROW' : 'TONIGHT',
        TonightKind.resume => 'CONTINUE',
        TonightKind.saved => 'MY LIST',
        TonightKind.archive => 'ARCHIVE',
      };

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final use24h = context.select<SettingsState, bool>((st) => st.use24h);
    final p = LayoutPalette.of(context);
    final tv = TvScope.of(context);
    final wide = tv || MediaQuery.sizeOf(context).width >= 800;
    final entries = _build(s);
    final sel = entries.isEmpty ? -1 : _sel.clamp(0, entries.length - 1);
    final now = DateTime.now();

    String t(DateTime d) => fmtTime(d, use24h: use24h);
    String timeOf(TonightEntry e) => tonightTimeLabel(e, t);

    Widget dayChip(TonightDay d) {
      final on = d == _day;
      return FocusSurface(
        radius: 24,
        semanticLabel: d.label,
        onTap: () => setState(() {
          _day = d;
          _sel = 0;
        }),
        builder: (_, __) => Container(
          padding: EdgeInsets.symmetric(
              horizontal: wide ? 20 : 14, vertical: wide ? 9 : 7),
          decoration: BoxDecoration(
            color: on ? _ink : Colors.transparent,
            border: Border.all(color: _ink),
            borderRadius: BorderRadius.circular(24),
          ),
          child: Text(d.label,
              style: TextStyle(
                  fontSize: wide ? 17 : 14,
                  fontWeight: FontWeight.w700,
                  color: on ? _paper : _ink)),
        ),
      );
    }

    Widget line(int i) {
      final e = entries[i];
      final focus = i == sel;
      final live = e.kind == TonightKind.live;
      final prog = e.programme;
      double? progress;
      if (live && prog != null) {
        final total = prog.end.difference(prog.start).inSeconds;
        if (total > 0) {
          progress =
              (now.difference(prog.start).inSeconds / total).clamp(0.0, 1.0);
        }
      }
      final sub = prog == null
          ? (e.kind == TonightKind.resume
              ? 'Pick up where you left off'
              : 'In My List')
          : (wide
              ? '${e.item.name} · ${t(prog.start)} – ${t(prog.end)}'
              : '${e.item.name} · ${prog.end.difference(prog.start).inMinutes} min');
      final art = e.item.poster;
      return IntrinsicHeight(
        child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          SizedBox(
            width: wide ? 84 : 66,
            child: Padding(
              padding: const EdgeInsets.only(top: 14),
              child:
                  Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                Text(
                    live && e.when != null && _day == TonightDay.now
                        ? t(e.when!)
                        : timeOf(e),
                    textAlign: TextAlign.end,
                    style: TextStyle(
                        fontFamily: 'serif',
                        fontSize: wide
                            ? (e.when == null ? 15 : 22)
                            : (e.when == null ? 12 : 17),
                        fontWeight: FontWeight.w700,
                        color: p.text)),
                if (live)
                  Text('NOW',
                      style: TextStyle(
                          fontSize: wide ? 11 : 10,
                          letterSpacing: 1.4,
                          fontWeight: FontWeight.w800,
                          color: p.muted)),
              ]),
            ),
          ),
          SizedBox(
            width: 28,
            child: Stack(children: [
              Positioned(
                  left: 13,
                  top: 0,
                  bottom: 0,
                  child: Container(
                      width: 2, color: p.accent.withValues(alpha: 0.35))),
              Positioned(
                left: 7,
                top: 19,
                child: Container(
                  width: 14,
                  height: 14,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: live ? p.accent : p.bg,
                    border: Border.all(color: p.accent, width: 3),
                  ),
                ),
              ),
            ]),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: FocusSurface(
                radius: 12,
                autofocus: tv && i == 0,
                semanticLabel: '${timeOf(e)} ${e.title}',
                onFocus: (f) {
                  if (f && _sel != i) setState(() => _sel = i);
                },
                onTap: () {
                  setState(() => _sel = i);
                  _open(e, s);
                },
                onLongPress: prog == null
                    ? null
                    : () => showProgrammeSheet(context, e.item, prog,
                        queue: s.shown.live),
                builder: (_, __) => Container(
                  decoration: BoxDecoration(
                    color: focus ? Colors.white : p.surface,
                    border: Border.all(
                        color: focus ? p.accent : p.line, width: focus ? 2 : 1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  padding:
                      EdgeInsets.fromLTRB(8, 8, 12, progress == null ? 8 : 12),
                  child: Stack(children: [
                    Row(children: [
                      Container(
                        width: wide ? 92 : 64,
                        height: wide ? 56 : 44,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(8),
                          gradient: LinearGradient(
                              colors: [p.accent2, _ink],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight),
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: art == null || art.isEmpty
                            ? null
                            : NetImage(art,
                                fit: BoxFit.cover,
                                fallback: () => const SizedBox.shrink()),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(e.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                      fontSize: wide ? 20 : 16,
                                      fontWeight: FontWeight.w800,
                                      color: p.text)),
                              const SizedBox(height: 2),
                              Text(sub,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                      fontSize: wide ? 15 : 12,
                                      color: p.muted)),
                            ]),
                      ),
                      const SizedBox(width: 8),
                      _Tag(_tag(e),
                          live: live, mine: e.kind == TonightKind.saved),
                    ]),
                    if (progress != null)
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: -6,
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(2),
                          child: LinearProgressIndicator(
                              value: progress,
                              minHeight: 3,
                              backgroundColor: p.surfaceHi,
                              color: p.accent),
                        ),
                      ),
                  ]),
                ),
              ),
            ),
          ),
        ]),
      );
    }

    final guideMissing = !s.hasGuideSource;
    final timeline = <Widget>[
      if (entries.isEmpty)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 24),
          child: Text(
            s.guideLoading
                ? 'Loading the TV guide...'
                : guideMissing
                    ? 'There is no TV guide for this source, so there is nothing to plan yet. Titles you start or save will show up here.'
                    : switch (_day) {
                        TonightDay.catchUp =>
                          'No programmes with an archive in the last day.',
                        TonightDay.tomorrow =>
                          'The guide has nothing for tomorrow yet.',
                        _ =>
                          'Nothing lined up. Favorite a channel or start a movie and it will appear here.',
                      },
            style: TextStyle(color: p.muted, fontSize: wide ? 18 : 15),
          ),
        )
      else
        for (var i = 0; i < entries.length; i++) line(i),
    ];

    final header = <Widget>[
      // The top bar already carries the name on a TV.
      if (!wide) ...[
        Text('STREAMBOSS',
            style: TextStyle(
                fontSize: 12,
                letterSpacing: 2.4,
                fontWeight: FontWeight.w800,
                color: p.muted)),
        const SizedBox(height: 4),
      ],
      Text('Tonight',
          style: TextStyle(
              fontFamily: 'serif',
              fontSize: wide ? 58 : 44,
              height: 1,
              fontWeight: FontWeight.w700,
              letterSpacing: -1,
              color: p.text)),
      const SizedBox(height: 6),
      Text(
        entries.isEmpty
            ? _dateLine(now)
            : '${_dateLine(now)}, ${entries.length} ${entries.length == 1 ? 'thing' : 'things'} lined up',
        style: TextStyle(
            fontFamily: 'serif',
            fontStyle: FontStyle.italic,
            fontSize: wide ? 19 : 15,
            color: p.accent),
      ),
      SizedBox(height: wide ? 16 : 12),
      SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(children: [
          for (final d in TonightDay.values)
            Padding(padding: const EdgeInsets.only(right: 8), child: dayChip(d))
        ]),
      ),
      SizedBox(height: wide ? 22 : 16),
    ];

    final list = ListView(
      padding: EdgeInsets.fromLTRB(
          wide ? 32 : 16, wide ? 20 : 12, wide ? 12 : 16, 24),
      children: [...header, ...timeline],
    );

    if (!wide) return ColoredBox(color: p.bg, child: list);
    return ColoredBox(
      color: p.bg,
      child: Row(children: [
        Expanded(flex: 6, child: list),
        Expanded(
          flex: 4,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 24, 28, 24),
            child: _Details(
              entry: sel < 0 ? null : entries[sel],
              time: sel < 0 ? '' : timeOf(entries[sel]),
              clock: t,
              onOpen: sel < 0 ? null : () => _open(entries[sel], s),
              onStart: sel < 0 ||
                      entries[sel].programme == null ||
                      !s.catchUpFor(entries[sel].item, entries[sel].programme!)
                  ? null
                  : () => openCatchUp(
                      context, entries[sel].item, entries[sel].programme!),
              onList:
                  sel < 0 ? null : () => s.toggleFavorite(entries[sel].item),
              inList: sel >= 0 && s.isFavorite(entries[sel].item),
            ),
          ),
        ),
      ]),
    );
  }
}

class _Tag extends StatelessWidget {
  final String text;
  final bool live, mine;
  const _Tag(this.text, {this.live = false, this.mine = false});

  @override
  Widget build(BuildContext context) {
    final p = LayoutPalette.of(context);
    final bg = live ? p.accent : (mine ? p.accent2 : p.surfaceHi);
    final fg = live || mine ? Colors.white : p.muted;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration:
          BoxDecoration(color: bg, borderRadius: BorderRadius.circular(20)),
      child: Text(text,
          style: TextStyle(
              fontSize: 11,
              letterSpacing: 1.2,
              fontWeight: FontWeight.w800,
              color: fg)),
    );
  }
}

/// The dark panel beside the timeline: the highlighted line in full, and what can be done with it.
class _Details extends StatelessWidget {
  final TonightEntry? entry;
  final String time;
  final String Function(DateTime) clock;
  final VoidCallback? onOpen, onStart, onList;
  final bool inList;
  const _Details({
    required this.entry,
    required this.time,
    required this.clock,
    required this.onOpen,
    required this.onStart,
    required this.onList,
    required this.inList,
  });

  @override
  Widget build(BuildContext context) {
    final p = LayoutPalette.of(context);
    final e = entry;
    final decoration =
        BoxDecoration(color: _ink, borderRadius: BorderRadius.circular(20));
    if (e == null) {
      return Container(
        decoration: decoration,
        padding: const EdgeInsets.all(24),
        alignment: Alignment.center,
        child: Text('Pick a line to see what it is.',
            style:
                TextStyle(color: _paper.withValues(alpha: 0.7), fontSize: 17)),
      );
    }
    final prog = e.programme;
    final live = e.kind == TonightKind.live;
    final desc =
        (prog?.desc?.isNotEmpty ?? false) ? prog!.desc! : (e.item.plot ?? '');
    final meta = prog == null
        ? (e.item.kind == MediaKind.series ? 'Series' : 'Movie')
        : '${e.item.name} · ${clock(prog.start)} – ${clock(prog.end)}';
    final art = e.item.poster;
    return Container(
      decoration: decoration,
      padding: const EdgeInsets.all(22),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          height: 150,
          width: double.infinity,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            gradient: LinearGradient(
                colors: [p.accent2, const Color(0xFF0B3B5C)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight),
          ),
          clipBehavior: Clip.antiAlias,
          child: Stack(fit: StackFit.expand, children: [
            if (art != null && art.isNotEmpty)
              NetImage(art,
                  fit: BoxFit.cover, fallback: () => const SizedBox.shrink()),
            Positioned(
                left: 10,
                top: 10,
                child: _Tag(live ? 'LIVE' : time.toUpperCase(), live: live)),
          ]),
        ),
        const SizedBox(height: 14),
        Text(e.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
                fontFamily: 'serif',
                fontSize: 28,
                height: 1.1,
                fontWeight: FontWeight.w700,
                color: _paper)),
        const SizedBox(height: 6),
        Text(meta,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style:
                TextStyle(fontSize: 14, color: _paper.withValues(alpha: 0.75))),
        const SizedBox(height: 10),
        if (desc.isNotEmpty)
          Text(desc,
              maxLines: 4,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  fontSize: 15,
                  height: 1.35,
                  color: _paper.withValues(alpha: 0.9))),
        const Spacer(),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.only(top: 10),
          decoration: BoxDecoration(
              border: Border(
                  top: BorderSide(color: _paper.withValues(alpha: 0.2)))),
          child: Text.rich(
              TextSpan(children: [
                const TextSpan(
                    text: 'Why it is here. ',
                    style:
                        TextStyle(fontWeight: FontWeight.w800, color: _paper)),
                TextSpan(
                    text: e.reason,
                    style: const TextStyle(color: Color(0xFFE9A58F))),
              ]),
              style: const TextStyle(fontSize: 13.5, height: 1.3)),
        ),
        const SizedBox(height: 14),
        Row(children: [
          Expanded(
            child: _Btn(
              label: live ? 'Watch now' : (prog == null ? 'Play' : 'Details'),
              icon:
                  live || prog == null ? Icons.play_arrow : Icons.info_outline,
              primary: true,
              onTap: onOpen,
            ),
          ),
          if (onStart != null) ...[
            const SizedBox(width: 8),
            Expanded(child: _Btn(label: 'From the start', onTap: onStart))
          ],
          const SizedBox(width: 8),
          _Btn(
              label: '',
              icon: inList ? Icons.check : Icons.add,
              onTap: onList,
              semantic: inList ? 'Remove from My List' : 'Add to My List'),
        ]),
      ]),
    );
  }
}

class _Btn extends StatelessWidget {
  final String label;
  final IconData? icon;
  final bool primary;
  final VoidCallback? onTap;
  final String? semantic;
  const _Btn(
      {required this.label,
      this.icon,
      this.primary = false,
      required this.onTap,
      this.semantic});

  @override
  Widget build(BuildContext context) {
    return FocusSurface(
      radius: 12,
      semanticLabel: semantic ?? label,
      onTap: onTap ?? () {},
      builder: (_, __) => Container(
        height: 44,
        padding: EdgeInsets.symmetric(horizontal: label.isEmpty ? 14 : 8),
        decoration: BoxDecoration(
          color: primary ? const Color(0xFFD8552F) : Colors.transparent,
          border: Border.all(
              color: primary
                  ? const Color(0xFFD8552F)
                  : _paper.withValues(alpha: 0.5)),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (icon != null)
                Icon(icon, size: 20, color: primary ? Colors.white : _paper),
              if (icon != null && label.isNotEmpty) const SizedBox(width: 6),
              if (label.isNotEmpty)
                Flexible(
                  child: Text(label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 14,
                          color: primary ? Colors.white : _paper)),
                ),
            ]),
      ),
    );
  }
}
