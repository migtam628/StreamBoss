import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../screens/my_lists_screen.dart';
import '../state/app_state.dart';
import '../widgets/tv.dart';
import 'common.dart';
import 'home_views.dart';
import 'shell_nav.dart';
import 'ui_layout.dart';

/// Hub's Home: a launcher of big colored tiles, with what you were watching underneath.
class HubHome extends StatelessWidget {
  const HubHome({super.key});

  static String greeting() {
    final h = DateTime.now().hour;
    return h < 5
        ? 'Good night'
        : (h < 12
            ? 'Good morning'
            : (h < 18 ? 'Good afternoon' : 'Good evening'));
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final c = s.shown;
    final tv = TvScope.of(context);
    final wide = tv || MediaQuery.sizeOf(context).width >= 800;
    final nav = ShellNav.maybeOf(context);
    void go(int i) => nav?.select(i);
    void favorites() => Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => const MyListsScreen()));
    final onNow = c.live.isEmpty ? null : c.live.first.name;

    Widget tile(String title, String sub, IconData icon, List<Color> colors,
            VoidCallback onTap,
            {bool autofocus = false,
            String? extra,
            bool big = false,
            bool small = false}) =>
        _HubTile(
            title: title,
            sub: sub,
            icon: icon,
            colors: colors,
            onTap: onTap,
            autofocus: autofocus,
            extra: extra,
            big: big,
            small: small,
            compact: !wide);

    final live = tile('Live TV', '${c.live.length} channels', Icons.live_tv,
        const [Color(0xFF1FC4AF), Color(0xFF0B5F78)], () => go(1),
        autofocus: tv,
        extra: onNow == null ? null : 'On now: $onNow',
        big: true);
    final movies = tile('Movies', '${c.movies.length} titles', Icons.movie,
        const [Color(0xFFFF5D8F), Color(0xFFA3214F)], () => go(3));
    final series = tile('Series', '${c.series.length} shows', Icons.layers,
        const [Color(0xFF8C6BFF), Color(0xFF43228F)], () => go(4));
    final guide = tile('Guide', 'Now and next', Icons.view_list,
        const [Color(0xFF4C8DFF), Color(0xFF1C3F96)], () => go(2));
    final favs = tile(
        'Favorites',
        '${s.favoriteItems.length} saved',
        Icons.star_border,
        const [Color(0xFFFFB02E), Color(0xFFB25A0A)],
        favorites);
    final search = tile('Search', '', Icons.search,
        const [Color(0xFF30334A), Color(0xFF262836)], () => go(5),
        small: true);
    final animeCount = s.animeCount;
    final anime = tile('Anime', wide ? '' : '$animeCount titles', Icons.auto_awesome,
        const [Color(0xFFFF7A59), Color(0xFF9C2F4A)], () => go(7),
        small: wide);
    final settings = tile('Settings', '', Icons.settings_outlined,
        const [Color(0xFF30334A), Color(0xFF262836)], () => go(6),
        small: true);

    final shelf = s.recents.isNotEmpty
        ? Shelf(title: 'Continue watching', items: s.recents)
        : Shelf(title: 'Live now', items: c.live.take(20).toList());

    final header = Padding(
      padding: EdgeInsets.fromLTRB(20, wide ? 8 : 16, 20, 12),
      child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
        Expanded(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(greeting(),
                style: TextStyle(
                    fontSize: wide ? 34 : 26,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.5)),
            Text('Pick a place, or pick up where you left off.',
                style: TextStyle(
                    color: LayoutPalette.of(context).muted,
                    fontSize: wide ? 17 : 14)),
          ]),
        ),
        if (wide) const NavClock(),
      ]),
    );

    if (wide) {
      return ListView(padding: const EdgeInsets.only(bottom: 16), children: [
        header,
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: SizedBox(
            height: 250,
            child: Row(children: [
              Expanded(flex: 3, child: live),
              const SizedBox(width: 12),
              Expanded(
                  flex: 2,
                  child: Column(children: [
                    Expanded(child: movies),
                    const SizedBox(height: 12),
                    Expanded(child: series)
                  ])),
              const SizedBox(width: 12),
              Expanded(
                  flex: 2,
                  child: Column(children: [
                    Expanded(child: guide),
                    const SizedBox(height: 12),
                    Expanded(child: favs)
                  ])),
              const SizedBox(width: 12),
              Expanded(
                  child: Column(children: [
                Expanded(child: search),
                if (s.animeVisible) ...[
                  const SizedBox(height: 8),
                  Expanded(child: anime),
                ],
                const SizedBox(height: 8),
                Expanded(child: settings)
              ])),
            ]),
          ),
        ),
        const SizedBox(height: 18),
        shelf,
      ]);
    }
    return ListView(padding: const EdgeInsets.only(bottom: 16), children: [
      header,
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Column(children: [
          SizedBox(height: 176, child: live),
          const SizedBox(height: 10),
          SizedBox(
              height: 110,
              child: Row(children: [
                Expanded(child: movies),
                const SizedBox(width: 10),
                Expanded(child: series)
              ])),
          const SizedBox(height: 10),
          SizedBox(
              height: 96,
              child: Row(children: [
                Expanded(child: guide),
                const SizedBox(width: 10),
                Expanded(child: favs)
              ])),
          if (s.animeVisible) ...[
            const SizedBox(height: 10),
            SizedBox(height: 84, child: anime),
          ],
        ]),
      ),
      const SizedBox(height: 16),
      shelf,
    ]);
  }
}

class _HubTile extends StatelessWidget {
  final String title, sub;
  final String? extra;
  final IconData icon;
  final List<Color> colors;
  final VoidCallback onTap;
  final bool autofocus, big, small, compact;
  const _HubTile({
    required this.title,
    required this.sub,
    required this.icon,
    required this.colors,
    required this.onTap,
    required this.autofocus,
    required this.big,
    required this.small,
    required this.compact,
    this.extra,
  });

  @override
  Widget build(BuildContext context) {
    final tv = TvScope.of(context);
    return FocusSurface(
      radius: 20,
      autofocus: autofocus,
      semanticLabel: title,
      onTap: onTap,
      builder: (_, focused) => AnimatedScale(
        scale: focused && tv ? 1.03 : 1,
        duration: const Duration(milliseconds: 100),
        child: Container(
          width: double.infinity,
          height: double.infinity,
          padding: EdgeInsets.all(compact ? 14 : 18),
          decoration: BoxDecoration(
              gradient: LinearGradient(
                  colors: colors,
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight)),
          child: small
              ? FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Icon(icon, size: 34, color: Colors.white),
                    const SizedBox(height: 6),
                    Text(title,
                        maxLines: 1,
                        style: const TextStyle(
                            fontWeight: FontWeight.w700, fontSize: 15)),
                  ]),
                )
              : big
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                          Icon(icon,
                              size: compact ? 30 : 40, color: Colors.white),
                          const Spacer(),
                          Text(title,
                              style: TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontSize: compact ? 22 : 28)),
                          Text(sub,
                              style: const TextStyle(
                                  color: Colors.white70, fontSize: 15)),
                          if (extra != null) ...[
                            const SizedBox(height: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 5),
                              decoration: BoxDecoration(
                                  color: Colors.black26,
                                  borderRadius: BorderRadius.circular(10)),
                              child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(Icons.circle,
                                        size: 9, color: Color(0xFFFF5B5B)),
                                    const SizedBox(width: 8),
                                    Flexible(
                                        child: Text(extra!,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style:
                                                const TextStyle(fontSize: 14))),
                                  ]),
                            ),
                          ],
                        ])
                  : Row(children: [
                      Icon(icon, size: compact ? 28 : 36, color: Colors.white),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                      fontWeight: FontWeight.w800,
                                      fontSize: compact ? 17 : 22)),
                              Text(sub,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                      color: Colors.white70, fontSize: 14)),
                            ]),
                      ),
                    ]),
        ),
      ),
    );
  }
}
