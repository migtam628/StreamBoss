import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/media.dart';
import '../services/crash_guard.dart';
import '../state/app_state.dart';
import '../state/settings_state.dart';
import '../widgets/tv.dart';
import 'browse_screen.dart';
import 'crash_notice.dart';
import 'guide_screen.dart';
import 'home_screen.dart';
import 'search_screen.dart';
import 'settings_screen.dart';

class Shell extends StatefulWidget {
  const Shell({super.key});

  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> {
  late int _i;
  // Tabs are built on first visit only, so e.g. the guide isn't downloaded at login.
  final _visited = <int>{};

  @override
  void initState() {
    super.initState();
    // 0 Home, 1 Live, 2 Guide, 3 Movies, 4 Series, 5 Search, 6 Settings
    _i = context.read<SettingsState>().startTab.clamp(0, _dests.length - 1);
    _visited.add(_i);
    WidgetsBinding.instance.addPostFrameCallback((_) => _crashNotice());
  }

  /// If the last playback session died, say so, and turn on Safe playback when it died while
  /// starting (hardware decoding or the video output is the usual culprit on some devices).
  void _crashNotice() {
    final r = CrashGuard.takeReport();
    if (r == null || !mounted) return;
    final st = context.read<SettingsState>();
    final wasSafe = st.decoder == 'software';
    final switched = r.duringStartup && !wasSafe;
    if (switched) st.set('decoder', 'software');
    showCrashNotice(context, r, switchedToSafe: switched, wasSafeAlready: wasSafe);
  }

  static const _dests = [
    (Icons.home_outlined, Icons.home, 'Home'),
    (Icons.live_tv_outlined, Icons.live_tv, 'Live'),
    (Icons.view_list_outlined, Icons.view_list, 'Guide'),
    (Icons.movie_outlined, Icons.movie, 'Movies'),
    (Icons.tv_outlined, Icons.tv, 'Series'),
    (Icons.search, Icons.search, 'Search'),
    (Icons.settings_outlined, Icons.settings, 'Settings'),
  ];

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final pages = [
      const HomeScreen(),
      BrowseScreen(kind: MediaKind.live, catalog: s.shown),
      const GuideScreen(),
      BrowseScreen(kind: MediaKind.movie, catalog: s.shown),
      BrowseScreen(kind: MediaKind.series, catalog: s.shown),
      const SearchScreen(),
      const SettingsScreen(),
    ];
    final tv = TvScope.of(context);
    final wide = tv || MediaQuery.sizeOf(context).width >= 800;
    final body = IndexedStack(
      index: _i,
      children: [
        for (var k = 0; k < pages.length; k++) _visited.contains(k) ? pages[k] : const SizedBox.shrink(),
      ],
    );

    // On a TV, Back from any tab returns to Home first; only Home lets Back leave the app.
    Widget guard(Widget child) => PopScope(
          canPop: !tv || _i == 0,
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop) setState(() => _i = 0);
          },
          child: child,
        );

    void select(int v) => setState(() {
          _i = v;
          _visited.add(v);
        });

    if (wide) {
      return guard(Scaffold(
        body: TvSafe(
          child: Row(children: [
            NavigationRail(
              selectedIndex: _i,
              onDestinationSelected: select,
              labelType: NavigationRailLabelType.all,
              destinations: [
                for (final d in _dests)
                  NavigationRailDestination(icon: Icon(d.$1), selectedIcon: Icon(d.$2), label: Text(d.$3)),
              ],
            ),
            Expanded(child: body),
          ]),
        ),
      ));
    }
    return Scaffold(
      body: SafeArea(child: body),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _i,
        onDestinationSelected: select,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        destinations: [
          for (final d in _dests)
            NavigationDestination(
                icon: Icon(d.$1), selectedIcon: Icon(d.$2), label: d.$3),
        ],
      ),
    );
  }
}
