import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/media.dart';
import '../screens/open_item.dart';
import '../services/madlib.dart';
import '../services/vod_filter.dart';
import '../state/app_state.dart';
import '../widgets/media_tile.dart';
import '../widgets/tv.dart';
import 'common.dart';
import 'ui_layout.dart';

/// Madlib's Home: "Tonight I feel like a [movie] that is [funny], [well rated], from [any year]."
/// Each bracket is a choice; the titles that fit are listed underneath, best rated first. A blank
/// opens a list of its words with how many titles each would leave.
class MadlibHome extends StatefulWidget {
  const MadlibHome({super.key});

  @override
  State<MadlibHome> createState() => _MadlibHomeState();
}

class _MadlibHomeState extends State<MadlibHome> {
  MadSentence _s = const MadSentence();

  Future<void> _pick<T>(String title, List<T> values, T current, String Function(T) label, MadSentence Function(T) apply,
      int Function(MadSentence) count) async {
    final p = LayoutPalette.of(context);
    final chosen = await showDialog<T>(
      context: context,
      builder: (ctx) => SimpleDialog(
        backgroundColor: p.surface,
        title: Text(title, style: TextStyle(color: p.text, fontWeight: FontWeight.w800)),
        children: [
          for (final v in values)
            Builder(builder: (_) {
              final n = count(apply(v));
              return ListTile(
                autofocus: v == current,
                enabled: n > 0 || v == current,
                selected: v == current,
                onTap: () => Navigator.pop(ctx, v),
                title: Text(label(v), style: TextStyle(fontSize: 20, fontWeight: v == current ? FontWeight.w800 : FontWeight.w500)),
                trailing: Text('$n', style: TextStyle(color: p.muted)),
              );
            }),
        ],
      ),
    );
    if (chosen != null && mounted) setState(() => _s = apply(chosen));
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final p = LayoutPalette.of(context);
    final tv = TvScope.of(context);
    final wide = tv || MediaQuery.sizeOf(context).width >= 800;
    final c = app.shown;
    List<MediaItem> matches(MadSentence s) => madlibMatches(s, c, categoryName: _catName(app));
    final items = matches(_s);
    final size = wide ? 38.0 : 26.0;

    Widget word(String text, VoidCallback onTap, {bool any = false, bool autofocus = false}) => FocusSurface(
          radius: 18,
          autofocus: autofocus && tv,
          semanticLabel: 'Change: $text',
          onTap: onTap,
          builder: (_, __) => Container(
            padding: EdgeInsets.symmetric(horizontal: wide ? 16 : 10, vertical: wide ? 4 : 2),
            decoration: BoxDecoration(
              color: any ? Colors.transparent : p.surfaceHi,
              border: Border(bottom: BorderSide(color: p.accent, width: 3)),
            ),
            child: Text(text, style: TextStyle(fontSize: size, fontWeight: FontWeight.w800, color: p.accent2)),
          ),
        );
    Widget plain(String t) => Text(t, style: TextStyle(fontSize: size, color: p.text, fontWeight: FontWeight.w500));

    return ListView(padding: EdgeInsets.fromLTRB(wide ? 32 : 16, wide ? 20 : 12, wide ? 32 : 16, 24), children: [
      Text('TONIGHT, YOUR WAY', style: TextStyle(fontSize: wide ? 16 : 13, letterSpacing: 2.5, fontWeight: FontWeight.w800, color: p.muted)),
      SizedBox(height: wide ? 14 : 8),
      Wrap(crossAxisAlignment: WrapCrossAlignment.center, spacing: 8, runSpacing: wide ? 14 : 10, children: [
        plain('Tonight I feel like a'),
        word(_s.kind.label, autofocus: true, () => _pick<MadKind>('I feel like a', MadKind.values, _s.kind, (v) => v.label, (v) => _s.copyWith(kind: v), (n) => matches(n).length)),
        plain('that is'),
        word(_s.mood.label, any: _s.mood == MadMood.any, () => _pick<MadMood>('that is', MadMood.values, _s.mood, (v) => v.label, (v) => _s.copyWith(mood: v), (n) => matches(n).length)),
        plain(','),
        word(_s.rating.label, any: _s.rating == MadRating.any, () => _pick<MadRating>('rated', MadRating.values, _s.rating, (v) => v.label, (v) => _s.copyWith(rating: v), (n) => matches(n).length)),
        plain(', from'),
        word(_s.era == Era.any ? 'any year' : _s.era.label, any: _s.era == Era.any, () => _pick<Era>('from', Era.values, _s.era, (v) => v == Era.any ? 'any year' : v.label, (v) => _s.copyWith(era: v), (n) => matches(n).length)),
        plain('.'),
      ]),
      SizedBox(height: wide ? 24 : 16),
      Text(items.isEmpty ? 'Nothing matches. Loosen a word.' : '${items.length} ${items.length == 1 ? 'title matches' : 'titles match'}. Best first:',
          style: TextStyle(fontSize: wide ? 22 : 16, fontWeight: FontWeight.w700, color: items.isEmpty ? p.muted : p.accent2)),
      const SizedBox(height: 10),
      if (items.isNotEmpty)
        SizedBox(
          height: (wide ? 250 : 190) + (tv ? 20 : 0),
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: EdgeInsets.symmetric(vertical: tv ? 12 : 4, horizontal: 4),
            itemCount: items.length.clamp(0, 30),
            separatorBuilder: (_, __) => SizedBox(width: tv ? 22 : 12),
            itemBuilder: (_, i) => AspectRatio(
              aspectRatio: items[i].kind == MediaKind.live ? 16 / 10 : 2 / 3,
              child: MediaTile(
                item: items[i],
                favorite: app.isFavorite(items[i]),
                onTap: () => openItem(context, items[i], queue: items[i].kind == MediaKind.live ? items : null),
                onLongPress: () => app.toggleFavorite(items[i]),
              ),
            ),
          ),
        ),
    ]);
  }

  String Function(MediaItem) _catName(AppState app) => (i) => i.kind == MediaKind.live ? app.liveCategoryName(i) : app.vodCategoryName(i);
}
