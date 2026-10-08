import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/media.dart';
import '../screens/open_item.dart';
import '../state/app_state.dart';
import '../widgets/media_tile.dart';
import '../widgets/tv.dart';
import 'common.dart';
import 'shell_nav.dart';
import 'ui_layout.dart';

/// Mood sits on a slow gradient from ink blue to dusty rose, with a soft peach glow low on the right.
class MoodBackdrop extends StatelessWidget {
  final Widget child;
  const MoodBackdrop({super.key, required this.child});

  @override
  Widget build(BuildContext context) => DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment(-0.1, -1),
            end: Alignment(0.1, 1),
            colors: [Color(0xFF131E3B), Color(0xFF243059), Color(0xFF52507F), Color(0xFFB0808F), Color(0xFFD9A199)],
            stops: [0.0, 0.36, 0.62, 0.86, 1.0],
          ),
        ),
        child: DecoratedBox(
          decoration: const BoxDecoration(
            gradient: RadialGradient(
                center: Alignment(0.8, 1.0), radius: 0.7, colors: [Color(0x8CFFD0B0), Color(0x00FFD0B0)]),
          ),
          child: child,
        ),
      );
}

class _Mood {
  final String label;
  final IconData icon;
  const _Mood(this.label, this.icon);
}

const _moods = [
  _Mood('Something live', Icons.live_tv_outlined),
  _Mood('A movie night', Icons.movie_outlined),
  _Mood('A short watch', Icons.timer_outlined),
  _Mood('Keep watching', Icons.play_circle_outline),
  _Mood('Kids', Icons.child_care_outlined),
  _Mood('Surprise me', Icons.auto_awesome_outlined),
];

final _kids = RegExp(r'(\bkids?\b|child|cartoon|animat|famil|junior|toddler|disney|nick)', caseSensitive: false);

/// The titles behind a mood, drawn from whatever the provider's data supports.
List<MediaItem> moodShelf(String mood, AppState s, {int surprise = 0}) {
  final c = s.shown;
  double rate(MediaItem e) => double.tryParse(e.rating ?? '') ?? 0;
  switch (mood) {
    case 'Something live':
      return c.live.take(12).toList();
    case 'A movie night':
      final m = [...c.movies]..sort((a, b) => rate(b).compareTo(rate(a)));
      return m.take(12).toList();
    case 'A short watch':
      // Episodes are short. Without runtimes in the data, series are the honest answer.
      return (c.series.isNotEmpty ? c.series : c.movies).take(12).toList();
    case 'Keep watching':
      return s.recents.take(12).toList();
    case 'Kids':
      final kidsCats = <String>{
        for (final cat in [...c.liveCategories, ...c.movieCategories, ...c.seriesCategories])
          if (_kids.hasMatch(cat.name)) cat.id
      };
      return [
        ...c.live.where((e) => kidsCats.contains(e.categoryId)),
        ...c.movies.where((e) => kidsCats.contains(e.categoryId)),
        ...c.series.where((e) => kidsCats.contains(e.categoryId)),
      ].take(12).toList();
    default:
      final all = [...c.movies, ...c.series, ...c.live];
      if (all.isEmpty) return const [];
      // A stable shuffle for this press, so the shelf does not jump on every rebuild.
      final out = <MediaItem>[];
      var i = (DateTime.now().day * 7919 + surprise * 104729) % all.length;
      for (var k = 0; k < 12 && k < all.length; k++) {
        out.add(all[i]);
        i = (i + 37 + k) % all.length;
      }
      return out.toSet().toList();
  }
}

/// Mood's Home: a greeting, a question, six big soft pills, and a shelf for the one you picked.
class MoodHome extends StatefulWidget {
  const MoodHome({super.key});

  @override
  State<MoodHome> createState() => _MoodHomeState();
}

class _MoodHomeState extends State<MoodHome> {
  int _sel = -1; // -1 = not chosen yet: show Keep watching if there is anything, else the first mood
  int _surprise = 0;

  String get _greeting {
    final h = DateTime.now().hour;
    return h < 5 ? 'Still up?' : (h < 12 ? 'Good morning.' : (h < 18 ? 'Good afternoon.' : 'Good evening.'));
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final p = LayoutPalette.of(context);
    final tv = TvScope.of(context);
    final wide = tv || MediaQuery.sizeOf(context).width >= 800;
    final sel = _sel >= 0 ? _sel : (s.recents.isNotEmpty ? 3 : 1);
    final items = moodShelf(_moods[sel].label, s, surprise: _surprise);

    Widget pill(int i) {
      final on = i == sel;
      return FocusSurface(
        radius: 34,
        autofocus: tv && i == sel,
        semanticLabel: _moods[i].label,
        onTap: () => setState(() {
          _sel = i;
          if (_moods[i].label == 'Surprise me') _surprise++;
        }),
        builder: (_, __) => Container(
          padding: EdgeInsets.symmetric(horizontal: wide ? 28 : 20, vertical: wide ? 18 : 14),
          color: on ? p.accent : p.text.withValues(alpha: 0.14),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(_moods[i].icon, size: wide ? 28 : 22, color: on ? p.onAccent : p.text),
            const SizedBox(width: 10),
            Text(_moods[i].label,
                style: TextStyle(
                    fontSize: wide ? 22 : 17, fontWeight: FontWeight.w800, color: on ? p.onAccent : p.text)),
          ]),
        ),
      );
    }

    return ListView(padding: EdgeInsets.fromLTRB(wide ? 24 : 16, wide ? 24 : 12, wide ? 24 : 16, 24), children: [
      if (wide)
        Wrap(spacing: 10, runSpacing: 8, children: [
          for (final (i, label) in const [(1, 'Live'), (2, 'Guide'), (3, 'Movies'), (4, 'Series'), (5, 'Search'), (6, 'Settings')])
            FocusSurface(
              radius: 20,
              semanticLabel: 'Browse $label',
              onTap: () => ShellNav.maybeOf(context)?.select(i),
              builder: (_, __) => Container(
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                color: p.text.withValues(alpha: 0.10),
                child: Text('Browse $label', style: TextStyle(color: p.text, fontWeight: FontWeight.w600, fontSize: 16)),
              ),
            ),
        ]),
      if (wide) const SizedBox(height: 18),
      Text(_greeting, style: TextStyle(fontSize: wide ? 22 : 18, color: p.accent, fontWeight: FontWeight.w700)),
      const SizedBox(height: 4),
      Text('What are you in the mood for?',
          style: TextStyle(fontSize: wide ? 46 : 30, height: 1.05, fontWeight: FontWeight.w800, letterSpacing: -0.5, color: p.text)),
      SizedBox(height: wide ? 24 : 16),
      Wrap(spacing: 12, runSpacing: 12, children: [for (var i = 0; i < _moods.length; i++) pill(i)]),
      SizedBox(height: wide ? 28 : 20),
      Text(_moods[sel].label, style: TextStyle(fontSize: wide ? 24 : 20, fontWeight: FontWeight.w800, color: p.text)),
      const SizedBox(height: 10),
      if (items.isEmpty)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Text(
              _moods[sel].label == 'Keep watching'
                  ? 'Nothing started yet. Pick another mood.'
                  : 'Nothing matched in your library. Try another mood.',
              style: TextStyle(color: p.muted, fontSize: wide ? 18 : 16)),
        )
      else
        SizedBox(
          height: (wide ? 230 : 190) + (tv ? 20 : 0),
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: EdgeInsets.symmetric(vertical: tv ? 12 : 4, horizontal: 4),
            itemCount: items.length,
            separatorBuilder: (_, __) => SizedBox(width: tv ? 22 : 12),
            itemBuilder: (_, i) => AspectRatio(
              aspectRatio: items[i].kind == MediaKind.live ? 16 / 10 : 2 / 3,
              child: MediaTile(
                item: items[i],
                favorite: s.isFavorite(items[i]),
                onTap: () => openItem(context, items[i], queue: items[i].kind == MediaKind.live ? items : null),
                onLongPress: () => s.toggleFavorite(items[i]),
              ),
            ),
          ),
        ),
    ]);
  }
}
