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

/// Name of screen [i] in [l]: Prime Time's Home is the guide, Hub's is the hub.
String destLabel(UiLayout l, int i) => switch ((l, i)) {
      (UiLayout.prime, 0) => 'Guide',
      (UiLayout.hub, 0) => 'Hub',
      (UiLayout.indexList, 0) => 'Index',
      (UiLayout.orbit, 0) => 'Orbit',
      (UiLayout.mood, 0) => 'Mood',
      (UiLayout.mosaic, 0) => 'Mosaic',
      (UiLayout.cable, 0) => 'Live',
      (UiLayout.cable, 1) => 'Channels',
      _ => kDests[i].label,
    };

IconData destIcon(UiLayout l, int i, {bool selected = false}) =>
    switch ((l, i)) {
      (UiLayout.prime, 0) =>
        selected ? Icons.view_list : Icons.view_list_outlined,
      (UiLayout.hub, 0) => selected ? Icons.apps : Icons.apps_outlined,
      (UiLayout.indexList, 0) =>
        selected ? Icons.format_list_bulleted : Icons.format_list_bulleted,
      (UiLayout.cable, 0) => selected ? Icons.live_tv : Icons.live_tv_outlined,
      (UiLayout.orbit, 0) => Icons.donut_large,
      (UiLayout.mood, 0) => selected ? Icons.mood : Icons.mood_outlined,
      (UiLayout.mosaic, 0) => selected ? Icons.grid_view_rounded : Icons.grid_view,
      (UiLayout.cable, 1) => selected ? Icons.list : Icons.list,
      _ => selected ? kDests[i].selectedIcon : kDests[i].icon,
    };

/// The tabs of a top navigation bar, in order (settings has its own button).
List<int> topTabs(UiLayout l) => switch (l) {
      UiLayout.prime => [0, 1, 3, 4, 5],
      UiLayout.coverflow => [0, 3, 4, 1, 2, 5],
      _ => [0, 1, 2, 3, 4, 5],
    };

/// The five items of the phone's bottom bar for each layout, then what "More" holds.
({List<int> bar, List<int> more}) phoneTabs(UiLayout l) => switch (l) {
      UiLayout.marquee => (bar: [0, 1, 2, 3], more: [4, 5, 6]),
      UiLayout.control => (bar: [0, 1, 2, 5], more: [3, 4, 6]),
      UiLayout.spotlight => (bar: [0, 1, 3, 4], more: [2, 5, 6]),
      UiLayout.prime => (bar: [0, 1, 3, 4], more: [5, 6]),
      UiLayout.coverflow => (bar: [0, 3, 4, 1], more: [2, 5, 6]),
      UiLayout.hub => (bar: [0, 5, 6], more: <int>[]),
      UiLayout.daylight => (bar: [0, 1, 3], more: [2, 4, 5, 6]),
      UiLayout.cable => (bar: [0, 2, 3], more: [1, 4, 5, 6]),
      // The list on Home is the menu, so the bar only appears inside a section (see IndexBackBar).
      UiLayout.indexList => (bar: [0, 5, 6], more: <int>[]),
      UiLayout.glass => (bar: [0, 1, 3], more: [2, 4, 5, 6]),
      UiLayout.bento => (bar: [0, 1, 3], more: [2, 4, 5, 6]),
      UiLayout.library => (bar: [0, 1, 3, 4], more: [2, 5, 6]),
      // The dial is the menu on a phone, so Orbit shows a bar only inside a section.
      UiLayout.orbit => (bar: [0, 5, 6], more: <int>[]),
      UiLayout.mood => (bar: [0, 1, 3], more: [2, 4, 5, 6]),
      UiLayout.mosaic => (bar: [0, 1, 3], more: [2, 4, 5, 6]),
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
    final hasMore = tabs.more.isNotEmpty;
    return NavigationBar(
      selectedIndex: inBar >= 0 ? inBar : (hasMore ? tabs.bar.length : 0),
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
              icon: Icon(destIcon(layout, i)),
              selectedIcon: Icon(destIcon(layout, i, selected: true)),
              label: destLabel(layout, i)),
        if (hasMore)
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
              leading: Icon(destIcon(layout, i, selected: i == index)),
              title: Text(destLabel(layout, i)),
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
  final bool pill, underline;

  /// Flat rectangular tab (Bento): sharp corners, solid fill.
  final bool block;
  const NavTab(
      {super.key,
      required this.label,
      this.icon,
      required this.selected,
      required this.onTap,
      this.pill = false,
      this.underline = false,
      this.block = false});

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
    final Color fill = widget.block
        ? (on ? p.text : p.surface)
        : widget.pill
        ? (on ? p.text : Colors.transparent)
        : (on && !widget.underline ? p.surfaceHi : Colors.transparent);
    final Color fg = widget.block
        ? (on ? p.bg : p.text)
        : widget.pill
        ? (on ? p.bg : p.text.withValues(alpha: 0.8))
        : (on ? p.text : p.muted);
    return Semantics(
      button: true,
      selected: on,
      label: widget.label,
      child: InkWell(
        borderRadius: BorderRadius.circular(widget.block ? 0 : (widget.pill ? 40 : 10)),
        onFocusChange: (f) => setState(() => _focused = f),
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 100),
          padding: EdgeInsets.symmetric(
              horizontal: widget.pill ? 18 : 14, vertical: widget.block ? 12 : 8),
          decoration: BoxDecoration(
            color: fill,
            borderRadius: widget.underline && !_focused
                ? null
                : BorderRadius.circular(widget.block ? 0 : (widget.pill ? 40 : 10)),
            border: widget.underline && !_focused
                ? Border(
                    bottom: BorderSide(
                        color: on ? p.accent : Colors.transparent, width: 3))
                : Border.all(
                    color: _focused
                        ? (tv ? p.ring : p.accent)
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

  @override
  Widget build(BuildContext context) {
    final p = LayoutPalette.of(context);
    final centered = layout == UiLayout.spotlight;
    final soft = layout == UiLayout.daylight;
    final pill = centered || soft;
    final flat = layout == UiLayout.bento;
    final underline = layout == UiLayout.coverflow;
    final tabs = [
      for (final i in topTabs(layout))
        NavTab(
            label: destLabel(layout, i),
            selected: i == index,
            pill: pill,
            underline: underline,
            block: flat,
            onTap: () => onSelect(i)),
    ];
    final settings = NavTab(
      label: 'Settings',
      icon: Icons.settings_outlined,
      selected: index == 6,
      pill: pill,
      underline: underline,
      block: flat,
      onTap: () => onSelect(6),
    );
    if (centered) {
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
                      color: p.wash(0.08),
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
          color: underline ? Colors.transparent : p.surface,
          border: underline ? null : Border(bottom: BorderSide(color: p.line))),
      child: Row(children: [
        if (soft) ...[
          Container(
              width: 12,
              height: 12,
              decoration:
                  BoxDecoration(color: p.accent, shape: BoxShape.circle)),
          const SizedBox(width: 8),
        ],
        Text(underline ? 'streamboss' : 'STREAMBOSS',
            style: TextStyle(
                color: underline || soft ? p.text : p.accent,
                fontWeight: FontWeight.w800,
                letterSpacing: underline ? -0.2 : 1.6,
                fontSize: underline ? 20 : 17)),
        const SizedBox(width: 24),
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(children: [
              for (final t in tabs)
                Padding(padding: EdgeInsets.only(right: flat ? 2 : 4), child: t)
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

/// The top bar of the launcher-style layouts (Hub, Index, Cable Box) on wide screens inside a
/// section: back to the layout's Home, the section's name, the time.
class HubBar extends StatelessWidget {
  final int index;
  final ValueChanged<int> onSelect;
  final UiLayout layout;
  const HubBar(
      {super.key,
      required this.index,
      required this.onSelect,
      this.layout = UiLayout.hub});

  @override
  Widget build(BuildContext context) {
    final p = LayoutPalette.of(context);
    return Container(
      height: 60,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration:
          BoxDecoration(border: Border(bottom: BorderSide(color: p.line))),
      child: Row(children: [
        NavTab(
            label: destLabel(layout, 0),
            icon: destIcon(layout, 0),
            selected: false,
            onTap: () => onSelect(0)),
        const SizedBox(width: 14),
        Text(destLabel(layout, index),
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
        const Spacer(),
        const NavClock(),
      ]),
    );
  }
}

/// Index and Orbit on a phone, inside a section: one slim bar that returns to their Home.
class IndexBackBar extends StatelessWidget {
  final int index;
  final ValueChanged<int> onSelect;
  final UiLayout layout;
  const IndexBackBar({super.key, required this.index, required this.onSelect, this.layout = UiLayout.indexList});

  @override
  Widget build(BuildContext context) {
    final p = LayoutPalette.of(context);
    return Material(
      color: p.surfaceHi,
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 56,
          child: InkWell(
            onTap: () => onSelect(0),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(children: [
                Icon(Icons.arrow_back, color: p.accent),
                const SizedBox(width: 12),
                Text(destLabel(layout, 0),
                    style: TextStyle(
                        color: p.accent,
                        fontWeight: FontWeight.w800,
                        fontSize: 18)),
                const Spacer(),
                Text(destLabel(layout, index),
                    style: TextStyle(color: p.text, fontSize: 16)),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}
