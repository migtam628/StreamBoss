import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../layouts/common.dart';
import '../layouts/ui_layout.dart';
import '../models/media.dart';
import '../services/channel_edits.dart' show ChannelEdit;
import '../services/channel_merge.dart' show channelQuality;
import '../services/countries.dart';
import '../services/languages.dart';
import '../services/xmltv.dart';
import '../state/app_state.dart';
import '../widgets/channel_sheet.dart';
import '../widgets/collections_sheet.dart';
import '../widgets/details_kit.dart';
import '../widgets/tv.dart';
import 'open_item.dart';

/// The page behind a live channel: what is on now and next, Watch live, From the start when the
/// provider keeps an archive, today's schedule (with replay marks), the facts about the channel, its
/// other copies and similar channels. OK on a channel in a list still just plays it; this page is
/// behind Info / Menu / press and hold.
class ChannelDetailsScreen extends StatefulWidget {
  final MediaItem channel;
  const ChannelDetailsScreen({super.key, required this.channel});

  @override
  State<ChannelDetailsScreen> createState() => _ChannelDetailsScreenState();
}

String? qualityLabel(String name) => switch (channelQuality(name)) {
      4 => '4K',
      3 => 'Full HD',
      2 => 'HD',
      0 => 'SD',
      _ => null,
    };

String clockTime(DateTime t, {bool h24 = false}) {
  if (h24) return '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
  final h = t.hour % 12 == 0 ? 12 : t.hour % 12;
  return '$h:${t.minute.toString().padLeft(2, '0')} ${t.hour < 12 ? 'AM' : 'PM'}';
}

class _ChannelDetailsScreenState extends State<ChannelDetailsScreen> {
  int _tab = 0;
  MediaItem get ch => widget.channel;

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final p = LayoutPalette.of(context);
    final now = DateTime.now();
    final all = s.programmesFor(ch);
    final today = [
      for (final x in all)
        if (x.end.isAfter(now.subtract(const Duration(hours: 3))) && x.start.isBefore(now.add(const Duration(hours: 24)))) x,
    ].take(48).toList();
    final onNow = today.where((x) => x.isNow).firstOrNull;
    final next = today.where((x) => x.start.isAfter(now)).firstOrNull;
    final cat = s.liveCategoryName(ch);
    final country = countryOf(cat) ?? countryOf(ch.name);
    final langCode = languageCodeOf(ch, cat);
    final quality = qualityLabel(ch.name);
    final rename = s.channelEdits.edits[ch.key];
    final copies = s.alternatesFor(ch);
    final similar = [
      for (final o in s.shown.live)
        if (o.categoryId == ch.categoryId && o.key != ch.key) o,
    ].take(18).toList();

    Widget button(IconData icon, String label, VoidCallback onTap, {bool primary = false, bool autofocus = false}) => primary
        ? FilledButton.icon(autofocus: autofocus, onPressed: onTap, icon: Icon(icon), label: Text(label))
        : OutlinedButton.icon(autofocus: autofocus, onPressed: onTap, icon: Icon(icon), label: Text(label));

    final chips = [
      if (cat.isNotEmpty) categoryLabel(cat),
      if (quality != null) quality,
      if (country != null) country.name,
      if (langCode != null) languageName(langCode),
      if (ch.archiveDays > 0) '${ch.archiveDays} days of catch-up',
      if (s.isDead(ch)) 'Offline at the last check',
    ];

    const tabs = ['Today', 'Details', 'Other copies', 'Similar channels'];
    return Scaffold(
      backgroundColor: p.bg,
      body: TvSafe(
        child: ListView(children: [
          DetailsHero(title: ch.name, poster: ch.poster, chips: chips, onBack: () => Navigator.of(context).maybePop()),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 4),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              if (onNow != null) ...[
                Row(children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                    decoration: BoxDecoration(color: Colors.red.shade600, borderRadius: BorderRadius.circular(4)),
                    child: const Text('LIVE', style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w800)),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(onNow.title,
                        maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: p.text, fontSize: 20, fontWeight: FontWeight.w800)),
                  ),
                ]),
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text('until ${clockTime(onNow.end)}${next == null ? '' : '  ·  Next: ${next.title} ${clockTime(next.start)}'}',
                      style: TextStyle(color: p.muted)),
                ),
                if (onNow.desc != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(onNow.desc!, maxLines: 3, overflow: TextOverflow.ellipsis, style: TextStyle(color: p.text, height: 1.35)),
                  ),
                const SizedBox(height: 14),
              ],
              Wrap(spacing: 10, runSpacing: 10, children: [
                button(Icons.live_tv, 'Watch live', () => openItem(context, ch, queue: s.shown.live), primary: true, autofocus: true),
                if (onNow != null && s.catchUpFor(ch, onNow))
                  button(Icons.history, 'From the start', () => openCatchUp(context, ch, onNow)),
                button(s.isFavorite(ch) ? Icons.star : Icons.star_border, s.isFavorite(ch) ? 'In My list' : 'My list', () => s.toggleFavorite(ch)),
                button(Icons.collections_bookmark_outlined, 'Collection', () => showCollectionsSheet(context, ch)),
                button(Icons.tune, 'Channel options', () => showChannelSheet(context, ch, details: false)),
              ]),
            ]),
          ),
          DetailTabs(labels: tabs, selected: _tab, onSelect: (i) => setState(() => _tab = i)),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
            child: switch (_tab) {
              0 => _today(p, s, today),
              1 => _details(s, cat, country, langCode, quality, rename),
              2 => _list(p, copies, 'No other copies of this channel in your library.', showQuality: true),
              _ => _list(p, similar, 'No other channels in this category.'),
            },
          ),
        ]),
      ),
    );
  }

  Widget _today(LayoutPalette p, AppState s, List<Programme> today) {
    if (today.isEmpty) {
      return Padding(
        padding: const EdgeInsets.only(top: 14),
        child: Text('No guide for this channel. Load a TV guide in Settings > Source & library.', style: TextStyle(color: p.muted)),
      );
    }
    return Column(children: [
      for (final x in today)
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: FocusSurface(
            radius: 10,
            semanticLabel: x.title,
            onTap: () {
              if (x.isNow) {
                openItem(context, ch, queue: s.shown.live);
              } else if (s.catchUpFor(ch, x)) {
                openCatchUp(context, ch, x);
              }
            },
            builder: (_, __) => Container(
              color: x.isNow ? p.accent.withValues(alpha: 0.18) : p.wash(0.06),
              padding: const EdgeInsets.all(12),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                SizedBox(width: 84, child: Text(clockTime(x.start), style: TextStyle(color: p.muted, fontWeight: FontWeight.w700))),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(x.title, style: TextStyle(color: p.text, fontWeight: FontWeight.w700)),
                    if (x.desc != null)
                      Text(x.desc!, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(color: p.muted, fontSize: 13)),
                  ]),
                ),
                if (x.isNow)
                  Text('NOW', style: TextStyle(color: p.accent, fontWeight: FontWeight.w800, fontSize: 12))
                else if (s.catchUpFor(ch, x))
                  Icon(Icons.history, color: p.accent, size: 20),
              ]),
            ),
          ),
        ),
    ]);
  }

  Widget _details(AppState s, String cat, Country? country, String? lang, String? quality, ChannelEdit? rename) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const DetailsHeading('Channel'),
      FactsTable([
        ('Name', ch.name),
        ('Provider name', rename?.name == null ? null : rename!.original),
        ('Category', cat),
        ('Country', country?.name),
        ('Language', lang == null ? null : languageName(lang)),
        ('Picture', quality),
        ('Guide id', ch.epgId),
        ('Catch-up', ch.archiveDays > 0 ? '${ch.archiveDays} days' : 'Not kept by the provider'),
        ('Last check', s.isDead(ch) ? 'Offline' : (s.deadKeys.isEmpty ? null : 'Online')),
        ('In My list', s.isFavorite(ch) ? 'Yes' : 'No'),
        ('Pinned', s.isPinned(ch.key) ? 'Yes' : null),
      ]),
    ]);
  }

  Widget _list(LayoutPalette p, List<MediaItem> items, String empty, {bool showQuality = false}) {
    if (items.isEmpty) {
      return Padding(padding: const EdgeInsets.only(top: 14), child: Text(empty, style: TextStyle(color: p.muted)));
    }
    return Column(children: [
      for (final o in items)
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: Icon(Icons.live_tv, color: p.accent),
          title: Text(o.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: p.text, fontWeight: FontWeight.w700)),
          subtitle: showQuality && qualityLabel(o.name) != null ? Text(qualityLabel(o.name)!) : null,
          onTap: () => openItem(context, o, queue: context.read<AppState>().shown.live),
        ),
    ]);
  }
}
