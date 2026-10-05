import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/time_format.dart';
import '../state/settings_state.dart';
import '../widgets/tv.dart';
import 'ui_layout.dart';

/// A main screen of the app, in the order the rest of the code indexes them
/// (0 Home, 1 Live, 2 Guide, 3 Movies, 4 Series, 5 Search, 6 Settings).
class Dest {
  final IconData icon, selectedIcon;
  final String label;
  const Dest(this.icon, this.selectedIcon, this.label);
}

const kDests = [
  Dest(Icons.home_outlined, Icons.home, 'Home'),
  Dest(Icons.live_tv_outlined, Icons.live_tv, 'Live'),
  Dest(Icons.view_list_outlined, Icons.view_list, 'Guide'),
  Dest(Icons.movie_outlined, Icons.movie, 'Movies'),
  Dest(Icons.tv_outlined, Icons.tv, 'Series'),
  Dest(Icons.search, Icons.search, 'Search'),
  Dest(Icons.settings_outlined, Icons.settings, 'Settings'),
];

/// Lets a page below the shell switch tabs (for example a search field that opens Search).
class ShellNav extends InheritedWidget {
  final int index;
  final ValueChanged<int> select;
  const ShellNav(
      {super.key,
      required this.index,
      required this.select,
      required super.child});

  static ShellNav? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ShellNav>();

  @override
  bool updateShouldNotify(ShellNav old) => old.index != index;
}

/// The five items of the phone's bottom bar for each layout, then what "More" holds.
({List<int> bar, List<int> more}) phoneTabs(UiLayout l) => switch (l) {
      UiLayout.marquee => (bar: [0, 1, 2, 3], more: [4, 5, 6]),
      UiLayout.control => (bar: [0, 1, 2, 5], more: [3, 4, 6]),
      UiLayout.spotlight => (bar: [0, 1, 3, 4], more: [2, 5, 6]),
    };

/// Bottom navigation for phones: four main screens and a More sheet for the rest.
class PhoneNav extends StatelessWidget {
  final UiLayout layout;
  final int index;
  final ValueChanged<int> onSelect;
  const PhoneNav(
      {super.key,
      required this.layout,
      required this.index,
      required this.onSelect});

  @override
  Widget build(BuildContext context) {
    final tabs = phoneTabs(layout);
    final inBar = tabs.bar.indexOf(index);
    return NavigationBar(
      selectedIndex: inBar >= 0 ? inBar : tabs.bar.length,
      onDestinationSelected: (v) {
        if (v < tabs.bar.length) {
          onSelect(tabs.bar[v]);
        } else {
          _more(context, tabs.more);
        }
      },
      labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
      destinations: [
        for (final i in tabs.bar)
          NavigationDestination(
              icon: Icon(kDests[i].icon),
              selectedIcon: Icon(kDests[i].selectedIcon),
              label: kDests[i].label),
        const NavigationDestination(
            icon: Icon(Icons.more_horiz), label: 'More'),
      ],
    );
  }

  void _more(BuildContext context, List<int> items) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          for (final i in items)
            ListTile(
              leading:
                  Icon(i == index ? kDests[i].selectedIcon : kDests[i].icon),
              title: Text(kDests[i].label),
              selected: i == index,
              onTap: () {
                Navigator.pop(ctx);
                onSelect(i);
              },
            ),
        ]),
      ),
    );
  }
}

/// One focusable item of a top navigation bar. On a TV the focus ring is the cursor.
class NavTab extends StatefulWidget {
  final String label;
  final IconData? icon;
  final bool selected;
  final VoidCallback onTap;
  final bool pill;
  const NavTab(
      {super.key,
      required this.label,
      this.icon,
      required this.selected,
      required this.onTap,
      this.pill = false});

  @override
  State<NavTab> createState() => _NavTabState();
}

class _NavTabState extends State<NavTab> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final p = LayoutPalette.of(context);
    final tv = TvScope.of(context);
    final on = widget.selected;
    final Color fill = widget.pill
        ? (on ? Colors.white : Colors.transparent)
        : (on ? p.surfaceHi : Colors.transparent);
    final Color fg = widget.pill
        ? (on ? const Color(0xFF1A0F27) : p.text.withValues(alpha: 0.8))
        : (on ? p.text : p.muted);
    return Semantics(
      button: true,
      selected: on,
      label: widget.label,
      child: InkWell(
        borderRadius: BorderRadius.circular(widget.pill ? 40 : 10),
        onFocusChange: (f) => setState(() => _focused = f),
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 100),
          padding: EdgeInsets.symmetric(
              horizontal: widget.pill ? 18 : 14, vertical: widget.pill ? 8 : 8),
          decoration: BoxDecoration(
            color: fill,
            borderRadius: BorderRadius.circular(widget.pill ? 40 : 10),
            border: Border.all(
              color: _focused
                  ? (tv ? Colors.white : p.accent)
                  : Colors.transparent,
              width: 3,
            ),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            if (widget.icon != null) ...[
              Icon(widget.icon, size: 20, color: fg),
              const SizedBox(width: 6)
            ],
            Text(widget.label,
                style: TextStyle(
                    color: fg,
                    fontWeight: on ? FontWeight.w700 : FontWeight.w600,
                    fontSize: 16)),
          ]),
        ),
      ),
    );
  }
}

/// Control Room's top bar: wordmark, tabs and a clock. [pill] gives Spotlight's centered pill instead.
class TopNav extends StatelessWidget {
  final UiLayout layout;
  final int index;
  final ValueChanged<int> onSelect;
  const TopNav(
      {super.key,
      required this.layout,
      required this.index,
      required this.onSelect});

  static const _tabs = [0, 1, 2, 3, 4, 5];

  @override
  Widget build(BuildContext context) {
    final p = LayoutPalette.of(context);
    final pill = layout == UiLayout.spotlight;
    final tabs = [
      for (final i in _tabs)
        NavTab(
            label: kDests[i].label,
            selected: i == index,
            pill: pill,
            onTap: () => onSelect(i)),
    ];
    final settings = NavTab(
      label: 'Settings',
      icon: Icons.settings_outlined,
      selected: index == 6,
      pill: pill,
      onTap: () => onSelect(6),
    );
    if (pill) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
        child: Row(children: [
          const Expanded(child: SizedBox()),
          // Scales down rather than overflowing on a narrow window.
          Expanded(
            flex: 6,
            child: Center(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(40)),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    for (final t in tabs)
                      Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 2),
                          child: t)
                  ]),
                ),
              ),
            ),
          ),
          Expanded(
              child: Align(
                  alignment: Alignment.centerRight,
                  child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerRight,
                      child: settings))),
        ]),
      );
    }
    return Container(
      height: 60,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
          color: p.surface, border: Border(bottom: BorderSide(color: p.line))),
      child: Row(children: [
        Text('STREAMBOSS',
            style: TextStyle(
                color: p.accent,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.6,
                fontSize: 17)),
        const SizedBox(width: 24),
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(children: [
              for (final t in tabs)
                Padding(padding: const EdgeInsets.only(right: 4), child: t)
            ]),
          ),
        ),
        settings,
        const SizedBox(width: 16),
        const NavClock(),
      ]),
    );
  }
}

/// The time, refreshed each minute.
class NavClock extends StatefulWidget {
  const NavClock({super.key});

  @override
  State<NavClock> createState() => _NavClockState();
}

class _NavClockState extends State<NavClock> {
  Timer? _t;

  @override
  void initState() {
    super.initState();
    _t = Timer.periodic(const Duration(seconds: 20), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _t?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = LayoutPalette.of(context);
    final use24h = context.select<SettingsState, bool>((s) => s.use24h);
    return Text(fmtTime(DateTime.now(), use24h: use24h),
        style: TextStyle(
            color: p.muted,
            fontFeatures: const [FontFeature.tabularFigures()],
            fontSize: 16));
  }
}
