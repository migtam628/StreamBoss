import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/media.dart';
import '../services/crash_guard.dart';
import '../state/app_state.dart';
import '../state/settings_state.dart';
import '../layouts/shell_nav.dart';
import '../layouts/ui_layout.dart';
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
    _i = context.read<SettingsState>().startTab.clamp(0, kDests.length - 1);
    _visited.add(_i);
    WidgetsBinding.instance.addPostFrameCallback((_) => _crashNotice());
  }

  /// If the last playback session died, say so, and step down to a safer way of playing when it
  /// died while starting: first the standard GPU video output (the TV hardware-surface output is the
  /// newest path), then software decoding. The video output or the decoder is the usual culprit.
  void _crashNotice() {
    final r = CrashGuard.takeReport();
    if (r == null || !mounted) return;
    final st = context.read<SettingsState>();
    final wasSafe = st.decoder == 'software';
    String? switchedTo;
    if (r.duringStartup) {
      if (st.surfaceOutput) {
        st.set('videoOutput', 'compat');
        switchedTo = 'compat';
      } else if (!wasSafe) {
        st.set('decoder', 'software');
        switchedTo = 'software';
      }
    }
    showCrashNotice(context, r, switchedTo: switchedTo, wasSafeAlready: wasSafe);
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final layout = context.select<SettingsState, UiLayout>((st) => st.layout);
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

    // On a TV, Back from any tab returns to Home first; only Home lets Back leave the app. Index and
    // Cable Box do the same on a phone because their Home is the root of everything else.
    final backHome = tv || layout == UiLayout.indexList || layout == UiLayout.cable;
    Widget guard(Widget child) => PopScope(
          canPop: !backHome || _i == 0,
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop) setState(() => _i = 0);
          },
          child: ShellNav(index: _i, select: select, child: child),
        );

    if (wide) {
      final Widget chrome;
      if (layout == UiLayout.marquee) {
        chrome = Row(children: [
          NavigationRail(
            selectedIndex: _i,
            onDestinationSelected: select,
            labelType: tv ? NavigationRailLabelType.selected : NavigationRailLabelType.all,
            destinations: [
              for (final d in kDests)
                NavigationRailDestination(icon: Icon(d.icon), selectedIcon: Icon(d.selectedIcon), label: Text(d.label)),
            ],
          ),
          Expanded(child: body),
        ]);
      } else if (layout == UiLayout.hub || layout == UiLayout.indexList || layout == UiLayout.cable) {
        chrome = Column(children: [
          if (_i != 0) HubBar(index: _i, onSelect: select, layout: layout),
          Expanded(child: body),
        ]);
      } else {
        chrome = Column(children: [
          TopNav(layout: layout, index: _i, onSelect: select),
          Expanded(child: body),
        ]);
      }
      return guard(Scaffold(
        body: _Backdrop(layout: layout, child: TvSafe(child: chrome)),
      ));
    }
    return guard(Scaffold(
      body: _Backdrop(layout: layout, child: SafeArea(child: body)),
      bottomNavigationBar: layout == UiLayout.indexList
          ? (_i == 0 ? null : IndexBackBar(index: _i, onSelect: select))
          : PhoneNav(layout: layout, index: _i, onSelect: select),
    ));
  }

  void select(int v) => setState(() {
        _i = v;
        _visited.add(v);
      });
}

/// Spotlight sits on soft colored glows; the other layouts use the plain background.
class _Backdrop extends StatelessWidget {
  final UiLayout layout;
  final Widget child;
  const _Backdrop({required this.layout, required this.child});

  @override
  Widget build(BuildContext context) {
    if (layout != UiLayout.spotlight) return child;
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: RadialGradient(center: Alignment(-0.7, -0.6), radius: 1.1, colors: [Color(0x557D6DFF), Color(0x00140C1D)]),
      ),
      child: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: RadialGradient(center: Alignment(1, 1), radius: 0.9, colors: [Color(0x40FF3D71), Color(0x00140C1D)]),
        ),
        child: child,
      ),
    );
  }
}
