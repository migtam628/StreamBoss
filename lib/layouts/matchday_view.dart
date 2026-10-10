import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/media.dart';
import '../screens/open_item.dart';
import '../services/matchday.dart';
import '../state/app_state.dart';
import '../state/settings_state.dart';
import '../widgets/tv.dart';
import 'common.dart';
import 'ui_layout.dart';

/// Matchday's Home: today's sport by kick-off. The guide's programmes on sports channels (and "A v B"
/// titles anywhere) become one line each, with the channels that carry the event. The match in
/// progress is first, tinted. OK plays the best channel; on a TV the panel beside the list shows the
/// others, and on a phone a tap lists them. Without guide data it falls back to the sports channels.
class MatchdayHome extends StatefulWidget {
  const MatchdayHome({super.key});

  @override
  State<MatchdayHome> createState() => _MatchdayHomeState();
}

class _MatchdayHomeState extends State<MatchdayHome> {
  Sport? _sport;
  int _sel = 0;
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    // The guide is not downloaded until something needs it; Matchday does, and keeps "now" honest.
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

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final p = LayoutPalette.of(context);
    final tv = TvScope.of(context);
    final wide = tv || MediaQuery.sizeOf(context).width >= 800;
    final use24h = context.select<SettingsState, bool>((st) => st.use24h);
    final now = DateTime.now();
    final local = now.toLocal();
    final until = DateTime(local.year, local.month, local.day).add(const Duration(days: 1, hours: 4));
    final all = buildMatchday(
      now: now,
      until: until,
      channels: s.shown.live,
      categoryName: s.liveCategoryName,
      programmesFor: s.programmesFor,
      isFavorite: s.isFavorite,
    );
    final sports = [for (final sp in Sport.values) if (all.any((e) => e.sport == sp)) sp];
    final sport = sports.contains(_sport) ? _sport : null;
    final events = sport == null ? all : [for (final e in all) if (e.sport == sport) e];
    final sel = events.isEmpty ? 0 : _sel.clamp(0, events.length - 1).toInt();

    void play(MatchEvent e, [MediaItem? ch]) => openItem(context, ch ?? e.channels.first, queue: e.channels);

    Future<void> channelSheet(MatchEvent e) => showModalBottomSheet<void>(
          context: context,
          backgroundColor: p.surface,
          builder: (ctx) => SafeArea(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(e.title, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: p.text)),
              ),
              for (final ch in e.channels)
                ListTile(
                  leading: Icon(Icons.play_arrow, color: p.accent),
                  title: Text(ch.name),
                  onTap: () {
                    Navigator.pop(ctx);
                    play(e, ch);
                  },
                ),
            ]),
          ),
        );

    if (s.shown.live.isEmpty) {
      return Center(child: Text('No live channels in this source.', style: TextStyle(color: p.muted)));
    }

    // No guide, or no sport in it: the sports channels themselves.
    if (all.isEmpty) {
      final sportChannels = [for (final c in s.shown.live) if (isSportCategory(s.liveCategoryName(c))) c];
      return ListView(padding: const EdgeInsets.all(16), children: [
        Text('MATCHDAY', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800, letterSpacing: 3, color: p.accent)),
        const SizedBox(height: 8),
        Text(
            s.guideLoading
                ? 'Loading the TV guide...'
                : s.hasGuideSource
                ? 'No sport found in today\'s guide.'
                : 'Matchday reads the TV guide, and this source has none. Add a guide in Settings to see the day\'s events.',
            style: TextStyle(color: p.muted, fontSize: wide ? 18 : 15)),
        const SizedBox(height: 14),
        if (sportChannels.isNotEmpty) Text('Sports channels', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: p.text)),
        for (final ch in sportChannels.take(40))
          ListTile(
            leading: Icon(Icons.sports_soccer, color: p.accent),
            title: Text(ch.name),
            onTap: () => openItem(context, ch, queue: sportChannels),
          ),
      ]);
    }

    Widget tab(String label, bool on, VoidCallback onTap) => Padding(
          padding: const EdgeInsets.only(right: 8),
          child: FocusSurface(
            radius: 10,
            semanticLabel: label,
            onTap: onTap,
            builder: (_, __) => Container(
              padding: EdgeInsets.symmetric(horizontal: wide ? 18 : 12, vertical: 8),
              decoration: BoxDecoration(
                color: on ? p.accent : Colors.transparent,
                border: Border.all(color: on ? p.accent : p.line),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(label, style: TextStyle(fontWeight: FontWeight.w700, color: on ? p.onAccent : p.muted)),
            ),
          ),
        );

    Widget row(int i) {
      final e = events[i];
      final live = e.isLive(now);
      final time = matchTimeLabel(e, now, use24h: use24h);
      return Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: FocusSurface(
          radius: 12,
          semanticLabel: '$time ${e.title}',
          onFocus: (f) {
            if (f && tv && _sel != i) setState(() => _sel = i);
          },
          onTap: () {
            if (tv) {
              play(e);
            } else if (e.channels.length == 1) {
              play(e);
            } else {
              channelSheet(e);
            }
          },
          builder: (_, __) => Container(
            padding: EdgeInsets.symmetric(horizontal: 14, vertical: wide ? 12 : 10),
            color: i == sel && tv ? p.surfaceHi : p.surface,
            child: Row(children: [
              SizedBox(
                width: wide ? 92 : 64,
                child: Text(time,
                    style: TextStyle(fontSize: wide ? 28 : 20, fontWeight: FontWeight.w800, color: live ? p.accent2 : p.text)),
              ),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(e.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: wide ? 20 : 16, fontWeight: FontWeight.w700, color: p.text)),
                  Text('${e.sport.label}  ·  ${e.channels.first.name}${e.channels.length > 1 ? '  +${e.channels.length - 1}' : ''}',
                      maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: wide ? 14 : 12, color: p.muted)),
                ]),
              ),
            ]),
          ),
        ),
      );
    }

    final list = ListView(padding: const EdgeInsets.fromLTRB(12, 4, 12, 16), children: [for (var i = 0; i < events.length; i++) row(i)]);

    final selected = events.isEmpty ? null : events[sel];
    final details = selected == null
        ? const SizedBox.shrink()
        : Container(
            margin: const EdgeInsets.fromLTRB(0, 4, 12, 16),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: p.surface, border: Border.all(color: p.line), borderRadius: BorderRadius.circular(14)),
            child: ListView(children: [
              Text(selected.title, style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: p.text)),
              const SizedBox(height: 4),
              Text(selected.sport.label, style: TextStyle(color: p.muted)),
              const SizedBox(height: 14),
              Text('WATCH ON', style: TextStyle(fontSize: 13, letterSpacing: 1.5, fontWeight: FontWeight.w800, color: p.muted)),
              const SizedBox(height: 8),
              for (var i = 0; i < selected.channels.length; i++)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: FocusSurface(
                    radius: 10,
                    semanticLabel: 'Watch on ${selected.channels[i].name}',
                    onTap: () => play(selected, selected.channels[i]),
                    builder: (_, __) => Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      color: i == 0 ? p.accent : p.surfaceHi,
                      child: Row(children: [
                        Icon(Icons.play_arrow, size: 20, color: i == 0 ? p.onAccent : p.text),
                        const SizedBox(width: 8),
                        Expanded(child: Text(selected.channels[i].name, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: FontWeight.w700, color: i == 0 ? p.onAccent : p.text))),
                      ]),
                    ),
                  ),
                ),
            ]),
          );

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(
        padding: EdgeInsets.fromLTRB(12, wide ? 12 : 8, 12, 8),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(children: [
            Text('MATCH', style: TextStyle(fontSize: wide ? 26 : 20, fontWeight: FontWeight.w800, letterSpacing: 3, color: p.text)),
            Text('DAY', style: TextStyle(fontSize: wide ? 26 : 20, fontWeight: FontWeight.w800, letterSpacing: 3, color: p.accent)),
            const SizedBox(width: 18),
            tab('All sport', sport == null, () => setState(() {
                  _sport = null;
                  _sel = 0;
                })),
            for (final sp in sports)
              tab(sp.label, sport == sp, () => setState(() {
                    _sport = sp;
                    _sel = 0;
                  })),
          ]),
        ),
      ),
      Expanded(child: wide ? Row(children: [Expanded(flex: 3, child: list), Expanded(flex: 2, child: details)]) : list),
    ]);
  }
}
