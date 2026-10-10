import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/media.dart';
import '../screens/open_item.dart';
import '../services/playground.dart';
import '../state/app_state.dart';
import '../state/profiles_state.dart';
import '../state/settings_state.dart';
import '../widgets/media_tile.dart';
import '../widgets/net_image.dart';
import '../widgets/pin_dialog.dart';
import '../widgets/tv.dart';
import 'common.dart';
import 'shell_nav.dart';
import 'ui_layout.dart';

const _ink = Color(0xFF2B2350);

/// Playground's Home: built for a Kids profile. A big "keep watching" card, six chunky tiles and a row of
/// picks. There is no search and no menu; Grown-ups asks for the PIN (when one is set) before Settings.
class PlaygroundHome extends StatelessWidget {
  const PlaygroundHome({super.key});

  Future<void> _grownUps(BuildContext context) async {
    final ps = Provider.of<ProfilesState?>(context, listen: false);
    if (ps != null && !await askPin(context, ps, title: 'Grown-ups only')) {
      return;
    }
    if (context.mounted) ShellNav.maybeOf(context)?.select(6);
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final st = context.watch<SettingsState>();
    final ps = Provider.of<ProfilesState?>(context);
    final p = LayoutPalette.of(context);
    final tv = TvScope.of(context);
    final wide = tv || MediaQuery.sizeOf(context).width >= 800;
    final now = DateTime.now();
    final c = s.shown;
    final favKeys = s.favoriteItems.map((e) => e.key).toSet();
    final tiles = [
      for (final t in PlayTile.values)
        if (playgroundItems(t, c, favKeys).isNotEmpty) t,
    ];
    final kids = kidsItems(c).map((e) => e.key).toSet();
    MediaItem? resume;
    for (final r in s.recents) {
      if (kids.contains(r.key) && r.kind != MediaKind.live) {
        resume = r;
        break;
      }
    }
    final picks = kidsItems(c)
        .where((i) => i.kind != MediaKind.live)
        .take(wide ? 6 : 4)
        .toList();
    final name =
        ps == null || ps.current.id == 'main' ? 'there' : ps.current.name;
    final left = untilBedtime(now, st.bedtime);
    final past = pastBedtime(now, st.bedtime);

    Widget pill(IconData icon, String text, {VoidCallback? onTap}) =>
        FocusSurface(
          radius: 24,
          semanticLabel: text,
          onTap: onTap ?? () {},
          builder: (_, __) => Container(
            padding: EdgeInsets.symmetric(
                horizontal: wide ? 18 : 12, vertical: wide ? 9 : 7),
            decoration: BoxDecoration(
                color: Colors.white, borderRadius: BorderRadius.circular(24)),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(icon, size: wide ? 20 : 16, color: p.accent),
              const SizedBox(width: 6),
              Text(text,
                  style: TextStyle(
                      fontSize: wide ? 16 : 13,
                      fontWeight: FontWeight.w600,
                      color: _ink)),
            ]),
          ),
        );

    final top = Row(children: [
      Container(
        width: wide ? 48 : 40,
        height: wide ? 48 : 40,
        alignment: Alignment.center,
        decoration: BoxDecoration(
            color: p.accent,
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 3)),
        child: Text(name.characters.first.toUpperCase(),
            style: TextStyle(
                color: Colors.white,
                fontSize: wide ? 24 : 20,
                fontWeight: FontWeight.w700)),
      ),
      const SizedBox(width: 12),
      Expanded(
          child: Text('Hi $name!',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  fontSize: wide ? 32 : 26,
                  fontWeight: FontWeight.w700,
                  color: _ink))),
      if (left != null)
        pill(Icons.schedule,
            wide ? bedtimeLabel(left) : '${left.inMinutes} min'),
      const SizedBox(width: 8),
      pill(Icons.mood, 'Grown-ups', onTap: () => _grownUps(context)),
    ]);

    Widget hero() {
      final r = resume!;
      return FocusSurface(
        radius: 24,
        semanticLabel: 'Keep watching ${r.name}',
        onTap: () => openItem(context, r),
        builder: (_, __) => AspectRatio(
          aspectRatio: wide ? 2.05 : 1.7,
          child: Stack(fit: StackFit.expand, children: [
            Container(
                decoration: BoxDecoration(
                    gradient: LinearGradient(
                        colors: [p.accent2, _ink],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight))),
            if (r.poster != null && r.poster!.isNotEmpty)
              NetImage(r.poster!,
                  fit: BoxFit.cover, fallback: () => const SizedBox.shrink()),
            const DecoratedBox(
                decoration: BoxDecoration(
                    gradient: LinearGradient(
                        begin: Alignment.center,
                        end: Alignment.bottomCenter,
                        colors: [Colors.transparent, Color(0xDD2B2350)]))),
            Positioned(
              left: 14,
              top: 12,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                decoration: BoxDecoration(
                    color: const Color(0xFFFFD23F),
                    borderRadius: BorderRadius.circular(20)),
                child: const Text('Keep watching',
                    style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: _ink,
                        fontSize: 14)),
              ),
            ),
            Positioned(
              right: 14,
              top: 12,
              child: Container(
                  width: 48,
                  height: 48,
                  decoration: const BoxDecoration(
                      color: Colors.white, shape: BoxShape.circle),
                  child: Icon(Icons.play_arrow, color: p.accent2, size: 30)),
            ),
            Positioned(
              left: 16,
              right: 16,
              bottom: 16,
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(r.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: wide ? 26 : 22,
                            fontWeight: FontWeight.w700)),
                  ]),
            ),
          ]),
        ),
      );
    }

    Widget tile(int i) {
      final t = tiles[i];
      return FocusSurface(
        radius: 22,
        autofocus: tv && i == 0,
        semanticLabel: t.label,
        onTap: () => Navigator.of(context)
            .push(MaterialPageRoute(builder: (_) => PlaygroundShelf(tile: t))),
        builder: (_, __) => Container(
          height: wide ? 118 : 104,
          decoration: BoxDecoration(
              color: t.color,
              borderRadius: BorderRadius.circular(22),
              boxShadow: const [
                BoxShadow(color: Color(0x382B2350), offset: Offset(0, 5))
              ]),
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(t.icon,
                size: wide ? 38 : 34, color: t.dark ? _ink : Colors.white),
            const SizedBox(height: 4),
            Text(t.label,
                style: TextStyle(
                    fontSize: wide ? 20 : 17,
                    fontWeight: FontWeight.w700,
                    color: t.dark ? _ink : Colors.white)),
          ]),
        ),
      );
    }

    final tileGrid = GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.all(6),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: wide ? 3 : 2,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        mainAxisExtent: wide ? 118 : 104,
      ),
      itemCount: tiles.length,
      itemBuilder: (_, i) => tile(i),
    );

    final allDone = Container(
      width: double.infinity,
      padding: const EdgeInsets.all(28),
      decoration:
          BoxDecoration(color: _ink, borderRadius: BorderRadius.circular(24)),
      child: Column(children: [
        const Icon(Icons.bedtime, color: Color(0xFFFFD23F), size: 56),
        const SizedBox(height: 10),
        const Text('All done for today',
            style: TextStyle(
                color: Colors.white,
                fontSize: 28,
                fontWeight: FontWeight.w700)),
        const SizedBox(height: 6),
        Text('It is bedtime. See you tomorrow!',
            style: TextStyle(
                color: Colors.white.withValues(alpha: 0.8), fontSize: 18)),
      ]),
    );

    final empty = Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Text(
        'No children\'s categories were found in this source. A grown-up can pick another source or layout in Settings.',
        style: TextStyle(fontSize: wide ? 20 : 16, color: p.muted),
      ),
    );

    final Widget body;
    if (past) {
      body = allDone;
    } else if (tiles.isEmpty) {
      body = empty;
    } else if (wide) {
      body = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (resume != null)
            Expanded(
                flex: 41,
                child:
                    Padding(padding: const EdgeInsets.all(6), child: hero())),
          Expanded(flex: resume == null ? 1 : 47, child: tileGrid),
        ]),
        if (picks.isNotEmpty) ...[
          const SizedBox(height: 14),
          const Text('Today\'s picks',
              style: TextStyle(
                  fontSize: 24, fontWeight: FontWeight.w700, color: _ink)),
          const SizedBox(height: 10),
          SizedBox(
            height: 150,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.all(6),
              itemCount: picks.length,
              separatorBuilder: (_, __) => const SizedBox(width: 14),
              itemBuilder: (_, i) => AspectRatio(
                aspectRatio: 1.35,
                child: MediaTile(
                    item: picks[i],
                    favorite: s.isFavorite(picks[i]),
                    onTap: () => openItem(context, picks[i]),
                    onLongPress: () => s.toggleFavorite(picks[i])),
              ),
            ),
          ),
        ],
      ]);
    } else {
      body = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (resume != null)
          Padding(padding: const EdgeInsets.all(6), child: hero()),
        tileGrid,
      ]);
    }

    return ColoredBox(
      color: p.bg,
      child: ListView(
        padding: EdgeInsets.fromLTRB(
            wide ? 32 : 16, wide ? 20 : 12, wide ? 32 : 16, 24),
        children: [top, SizedBox(height: wide ? 18 : 14), body],
      ),
    );
  }
}

/// What one tile holds, as a grid of posters.
class PlaygroundShelf extends StatelessWidget {
  final PlayTile tile;
  const PlaygroundShelf({super.key, required this.tile});

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final p = LayoutPalette.of(context);
    final tv = TvScope.of(context);
    final items = playgroundItems(
        tile, s.shown, s.favoriteItems.map((e) => e.key).toSet());
    final live = items.where((e) => e.kind == MediaKind.live).toList();
    return Scaffold(
      backgroundColor: p.bg,
      body: SafeArea(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
            child: Row(children: [
              FocusSurface(
                radius: 28,
                autofocus: false,
                semanticLabel: 'Back',
                onTap: () => Navigator.of(context).maybePop(),
                builder: (_, __) => Container(
                  width: 52,
                  height: 52,
                  decoration:
                      BoxDecoration(color: tile.color, shape: BoxShape.circle),
                  child: Icon(Icons.arrow_back,
                      color: tile.dark ? _ink : Colors.white, size: 28),
                ),
              ),
              const SizedBox(width: 14),
              Text(tile.label,
                  style: const TextStyle(
                      fontSize: 34, fontWeight: FontWeight.w700, color: _ink)),
            ]),
          ),
          Expanded(
            child: GridView.builder(
              padding: const EdgeInsets.all(20),
              gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: tv ? 200 : 160,
                  childAspectRatio: 2 / 3,
                  crossAxisSpacing: 14,
                  mainAxisSpacing: 14),
              itemCount: items.length,
              itemBuilder: (_, i) => MediaTile(
                item: items[i],
                favorite: s.isFavorite(items[i]),
                autofocus: tv && i == 0,
                onTap: () => openItem(context, items[i],
                    queue: items[i].kind == MediaKind.live ? live : null),
                onLongPress: () => s.toggleFavorite(items[i]),
              ),
            ),
          ),
        ]),
      ),
    );
  }
}
