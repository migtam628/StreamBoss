import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/media.dart';
import '../screens/open_item.dart';
import '../services/console_commands.dart';
import '../services/search.dart';
import '../state/app_state.dart';
import '../state/profiles_state.dart';
import '../state/settings_state.dart';
import '../services/time_format.dart';
import '../widgets/live_preview.dart';
import '../widgets/net_image.dart';
import '../widgets/tv.dart';
import 'common.dart';
import 'shell_nav.dart';
import 'ui_layout.dart';
import '../widgets/channel_sheet.dart';
import '../widgets/tv_text_field.dart';

const _mono = TextStyle(
    fontFamily: 'monospace',
    fontFamilyFallback: ['Menlo', 'Consolas', 'Courier New']);

/// Console's Home: a prompt. Type to find channels, movies and series (the search ranks them as the
/// Search screen does), or start with a slash for a command (/live, /guide, /list ...). With nothing
/// typed it lists what you were watching and what you saved.
class ConsoleHome extends StatefulWidget {
  const ConsoleHome({super.key});

  @override
  State<ConsoleHome> createState() => _ConsoleHomeState();
}

enum _Kind { all, live, movie, series }

class _ConsoleHomeState extends State<ConsoleHome> {
  final _text = TextEditingController();
  final _prompt = FocusNode(debugLabel: 'console prompt');
  _Kind _kind = _Kind.all;
  MediaItem? _hover;
  String _q = '';

  @override
  void dispose() {
    _text.dispose();
    _prompt.dispose();
    super.dispose();
  }

  /// What the list shows for the current input: a title and the items under it, in groups.
  List<(String, List<MediaItem>)> _groups(AppState s) {
    final raw = _q.trim();
    if (raw.startsWith('/')) {
      final c = exactCommand(raw);
      if (c?.name == '/list') return [('MY LIST', s.favoriteItems)];
      if (c?.name == '/recent') return [('WATCHED LATELY', s.recents)];
      return const [];
    }
    if (raw.length < 2) {
      return [
        if (s.recents.isNotEmpty)
          ('CONTINUE WATCHING', s.recents.take(8).toList()),
        if (s.favoriteItems.isNotEmpty)
          ('MY LIST', s.favoriteItems.take(8).toList()),
      ];
    }
    final hits = s.searchIndex.search(raw,
        favorites: s.favorites,
        recent: {for (final r in s.recents) r.key},
        filters: SearchFilters(
            kinds: switch (_kind) {
          _Kind.all => const {},
          _Kind.live => const {MediaKind.live},
          _Kind.movie => const {MediaKind.movie},
          _Kind.series => const {MediaKind.series},
        }));
    List<MediaItem> of(MediaKind k) => [
          for (final h in hits)
            if (h.kind == k) h
        ];
    return [
      for (final (label, k) in const [
        ('CHANNELS', MediaKind.live),
        ('MOVIES', MediaKind.movie),
        ('SERIES', MediaKind.series)
      ])
        if (of(k).isNotEmpty) (label, of(k)),
    ];
  }

  void _run(AppState s, List<(String, List<MediaItem>)> groups) {
    final raw = _text.text.trim();
    if (raw.startsWith('/')) {
      final c = exactCommand(raw);
      if (c?.tab != null) {
        _text.clear();
        setState(() => _q = '');
        ShellNav.maybeOf(context)?.select(c!.tab!);
      } else if (c != null) {
        setState(() => _q = c.name);
        _text.text = c.name;
      }
      return;
    }
    final first = groups.expand((g) => g.$2).firstOrNull;
    if (first == null) return;
    s.rememberSearch(raw);
    final live = groups
        .expand((g) => g.$2)
        .where((i) => i.kind == MediaKind.live)
        .toList();
    openItem(context, first, queue: first.kind == MediaKind.live ? live : null);
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final st = context.watch<SettingsState>();
    final ps = Provider.of<ProfilesState?>(context);
    final p = LayoutPalette.of(context);
    final tv = TvScope.of(context);
    final wide = tv || MediaQuery.sizeOf(context).width >= 800;
    final groups = _groups(s);
    final flat = [for (final g in groups) ...g.$2];
    final total = flat.length;
    final cmds = matchCommands(_q);
    final preview = _hover != null && flat.any((i) => i.key == _hover!.key)
        ? _hover
        : (flat.isEmpty ? null : flat.first);
    final fs = wide ? 1.0 : 0.85;

    TextStyle t(double size, Color c, {FontWeight w = FontWeight.w400}) =>
        _mono.copyWith(fontSize: size * fs, color: c, fontWeight: w);

    Widget kindChip(_Kind k, String label, int n) {
      final on = _kind == k;
      return FocusSurface(
        radius: 6,
        semanticLabel: label,
        onTap: () => setState(() => _kind = k),
        builder: (_, __) => Container(
          padding: EdgeInsets.symmetric(
              horizontal: wide ? 12 : 9, vertical: wide ? 5 : 4),
          decoration: BoxDecoration(
            color: on ? p.accent : Colors.transparent,
            border: Border.all(color: on ? p.accent : p.line),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(n < 0 ? label : '$label $n',
              style: t(15, on ? p.bg : p.accent2,
                  w: on ? FontWeight.w700 : FontWeight.w400)),
        ),
      );
    }

    int count(MediaKind k) => flat.where((i) => i.kind == k).length;
    final searching = _q.trim().length >= 2 && !_q.trim().startsWith('/');

    Widget row(MediaItem i, int n) {
      final live = i.kind == MediaKind.live;
      final cat = live ? s.liveCategoryName(i) : '';
      final detail = live
          ? (s.programmesFor(i).where((x) => x.isNow).firstOrNull?.title ?? cat)
          : [
              if (i.rating != null && i.rating!.isNotEmpty && i.rating != '0')
                '★ ${i.rating}'
            ].join(' ');
      return FocusSurface(
        radius: 4,
        semanticLabel: i.name,
        onFocus: (f) {
          if (f && _hover?.key != i.key) setState(() => _hover = i);
        },
        onTap: () {
          if (searching) s.rememberSearch(_q);
          openItem(context, i,
              queue: live
                  ? flat.where((x) => x.kind == MediaKind.live).toList()
                  : null);
        },
        onLongPress: () => itemMenu(context, i),
        builder: (ctx, focused) {
          final c = focused ? p.bg : p.text;
          final dim = focused ? p.bg : p.muted;
          return Container(
            color: focused ? p.accent : Colors.transparent,
            padding:
                EdgeInsets.symmetric(horizontal: 10, vertical: wide ? 9 : 8),
            child: Row(children: [
              SizedBox(
                  width: wide ? 44 : 30,
                  child: Text(live ? '${n + 1}' : '·', style: t(15, dim))),
              Expanded(
                  child: Text(i.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: t(16, c,
                          w: focused ? FontWeight.w700 : FontWeight.w400))),
              if (s.isFavorite(i))
                Text('♥ ', style: t(14, focused ? p.bg : p.accent)),
              if (detail.isNotEmpty)
                Flexible(
                    flex: 0,
                    child: ConstrainedBox(
                        constraints: BoxConstraints(maxWidth: wide ? 220 : 110),
                        child: Text(detail,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: t(13, dim)))),
            ]),
          );
        },
      );
    }

    final list = <Widget>[];
    var n = 0;
    if (cmds.isNotEmpty) {
      for (final c in cmds) {
        list.add(FocusSurface(
          radius: 4,
          semanticLabel: c.name,
          onTap: () {
            _text.text = c.name;
            setState(() => _q = c.name);
            _run(s, groups);
          },
          builder: (_, focused) => Container(
            color: focused ? p.accent : Colors.transparent,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
            child: Row(children: [
              SizedBox(
                  width: wide ? 120 : 90,
                  child: Text(c.name,
                      style: t(16, focused ? p.bg : p.accent,
                          w: FontWeight.w700))),
              Expanded(
                  child: Text(c.help, style: t(14, focused ? p.bg : p.muted))),
            ]),
          ),
        ));
      }
    }
    for (final g in groups) {
      list.add(Padding(
        padding: const EdgeInsets.fromLTRB(10, 14, 10, 4),
        child: Container(
          decoration:
              BoxDecoration(border: Border(bottom: BorderSide(color: p.line))),
          padding: const EdgeInsets.only(bottom: 4),
          child: Row(children: [
            Text(g.$1,
                style: t(12, p.accent, w: FontWeight.w700)
                    .copyWith(letterSpacing: 2)),
            const SizedBox(width: 10),
            Text('${g.$2.length}', style: t(12, p.muted)),
          ]),
        ),
      ));
      for (final i in g.$2) {
        list.add(row(i, n++));
      }
    }
    if (list.isEmpty) {
      list.add(Padding(
        padding: const EdgeInsets.all(18),
        child: Text(
          searching
              ? 'No match for "${_q.trim()}".'
              : 'Type to find a channel, movie or series.\nStart with / for commands, such as /live or /guide.',
          style: t(15, p.muted).copyWith(height: 1.6),
        ),
      ));
      if (!searching && s.recentSearches.isNotEmpty) {
        list.add(Padding(
          padding: const EdgeInsets.fromLTRB(10, 6, 10, 0),
          child: Wrap(spacing: 8, runSpacing: 8, children: [
            for (final r in s.recentSearches.take(6))
              FocusSurface(
                radius: 6,
                semanticLabel: 'Search $r',
                onTap: () {
                  _text.text = r;
                  setState(() => _q = r);
                },
                builder: (_, __) => Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                      border: Border.all(color: p.line),
                      borderRadius: BorderRadius.circular(6)),
                  child: Text(r, style: t(14, p.accent2)),
                ),
              ),
          ]),
        ));
      }
    }

    final promptBox = Container(
      margin:
          EdgeInsets.fromLTRB(wide ? 24 : 12, wide ? 12 : 8, wide ? 24 : 12, 8),
      padding: EdgeInsets.symmetric(horizontal: 14, vertical: wide ? 6 : 2),
      decoration: BoxDecoration(
        border: Border.all(color: p.accent, width: 2),
        borderRadius: BorderRadius.circular(10),
        boxShadow: [
          BoxShadow(color: p.accent.withValues(alpha: 0.18), blurRadius: 16)
        ],
      ),
      child: Row(children: [
        Text('›', style: t(26, p.accent, w: FontWeight.w700)),
        const SizedBox(width: 12),
        Expanded(
          child: TvTextField(
            controller: _text,
            focusNode: _prompt,
            autofocus: !tv,
            cursorColor: p.accent,
            cursorWidth: 10,
            cursorRadius: Radius.zero,
            style: t(wide ? 26 : 20, p.text),
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              filled: false,
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
              hintText: 'find something, or type /',
              hintStyle: t(wide ? 22 : 18, p.muted),
            ),
            onChanged: (v) => setState(() {
              _q = v;
              _hover = null;
            }),
            onSubmitted: (_) => _run(s, groups),
          ),
        ),
        if (searching)
          Text('$total result${total == 1 ? '' : 's'}', style: t(13, p.muted)),
      ]),
    );

    final chips = Align(
        alignment: Alignment.centerLeft,
        child: Padding(
          padding: EdgeInsets.fromLTRB(wide ? 24 : 12, 0, 12, 4),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(children: [
              kindChip(_Kind.all, 'all', searching ? total : -1),
              const SizedBox(width: 8),
              kindChip(_Kind.live, 'channels',
                  searching ? count(MediaKind.live) : -1),
              const SizedBox(width: 8),
              kindChip(_Kind.movie, 'movies',
                  searching ? count(MediaKind.movie) : -1),
              const SizedBox(width: 8),
              kindChip(_Kind.series, 'series',
                  searching ? count(MediaKind.series) : -1),
            ]),
          ),
        ));

    final status = Container(
      color: p.surface,
      padding: EdgeInsets.symmetric(horizontal: wide ? 24 : 12, vertical: 6),
      child: Row(children: [
        Expanded(
          child: Text(
            '${s.searchIndex.length} items · ${s.sourceCount} source${s.sourceCount == 1 ? '' : 's'}${ps != null && ps.multiple ? ' · ${ps.current.name}' : ''} · ${fmtTime(DateTime.now(), use24h: st.use24h)}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: t(12, p.muted),
          ),
        ),
        if (wide)
          Text('↑↓ move   OK open   hold OK save', style: t(12, p.muted)),
      ]),
    );

    final listView = ListView(
        padding: const EdgeInsets.fromLTRB(14, 0, 14, 12), children: list);

    Widget previewPane() {
      final i = preview;
      if (i == null) return const SizedBox.shrink();
      final live = i.kind == MediaKind.live;
      final desc = live
          ? (s.programmesFor(i).where((x) => x.isNow).firstOrNull?.desc ?? '')
          : (i.plot ?? '');
      return Container(
        margin: const EdgeInsets.fromLTRB(0, 4, 24, 12),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
            border: Border.all(color: p.line),
            borderRadius: BorderRadius.circular(8)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          AspectRatio(
            aspectRatio: 16 / 9,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: Container(
                color: p.surfaceHi,
                child: live
                    ? LivePreview(
                        key: ValueKey(i.key),
                        channel: i,
                        fallback: i.poster == null
                            ? const SizedBox.shrink()
                            : Padding(
                                padding: const EdgeInsets.all(14),
                                child: NetImage(i.poster!,
                                    fit: BoxFit.contain,
                                    fallback: () => const SizedBox.shrink())),
                      )
                    : (i.poster == null
                        ? const SizedBox.shrink()
                        : NetImage(i.poster!,
                            fit: BoxFit.cover,
                            fallback: () => const SizedBox.shrink())),
              ),
            ),
          ),
          const SizedBox(height: 10),
          Text(i.name,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: t(20, p.text, w: FontWeight.w700)),
          const SizedBox(height: 4),
          Text(
            [
              live
                  ? 'channel'
                  : (i.kind == MediaKind.series ? 'series' : 'movie'),
              if (i.rating != null && i.rating!.isNotEmpty && i.rating != '0')
                '★ ${i.rating}'
            ].join(' · '),
            style: t(13, p.muted),
          ),
          if (desc.isNotEmpty) ...[
            const SizedBox(height: 8),
            Flexible(
                child: Text(desc,
                    maxLines: 6,
                    overflow: TextOverflow.ellipsis,
                    style: t(13, p.accent2).copyWith(height: 1.4))),
          ],
        ]),
      );
    }

    return ColoredBox(
      color: p.bg,
      child: Column(children: [
        promptBox,
        chips,
        Expanded(
          child: wide
              ? Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Expanded(
                      flex: 58,
                      child: Padding(
                          padding: const EdgeInsets.only(left: 10),
                          child: listView)),
                  Expanded(flex: 36, child: previewPane()),
                ])
              : listView,
        ),
        status,
      ]),
    );
  }
}
