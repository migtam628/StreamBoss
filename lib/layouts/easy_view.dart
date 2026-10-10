import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/media.dart';
import '../screens/open_item.dart';
import '../state/app_state.dart';
import '../widgets/tv.dart';
import 'common.dart';
import 'shell_nav.dart';
import 'ui_layout.dart';

/// Easy's Home: three huge buttons and nothing else. Watch TV opens the channel you were last on,
/// Movies and shows and Find open those screens, and a bar offers what you were watching. Black,
/// white and one yellow, large text, a thick double focus ring. There is no menu: Back from any screen
/// comes here, and Settings is a small button at the bottom.
class EasyHome extends StatelessWidget {
  const EasyHome({super.key});

  String get _greeting {
    final h = DateTime.now().hour;
    return h < 5 ? 'Still up?' : (h < 12 ? 'Good morning' : (h < 18 ? 'Good afternoon' : 'Good evening'));
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final p = LayoutPalette.of(context);
    final tv = TvScope.of(context);
    final wide = tv || MediaQuery.sizeOf(context).width >= 800;
    final live = s.shown.live;
    final lastLive = s.recents.where((e) => e.kind == MediaKind.live).firstOrNull;
    final resume = s.recents.where((e) => e.kind != MediaKind.live).firstOrNull;

    void watchTv() {
      if (live.isEmpty) {
        ShellNav.maybeOf(context)?.select(1);
        return;
      }
      final ch = lastLive == null ? live.first : (live.where((c) => c.key == lastLive.key).firstOrNull ?? live.first);
      openItem(context, ch, queue: live);
    }

    Widget big(String label, String hint, IconData icon, Color bg, Color fg, VoidCallback onTap, {bool autofocus = false}) {
      return FocusSurface(
        radius: 28,
        autofocus: autofocus && tv,
        semanticLabel: label,
        onTap: onTap,
        builder: (_, __) => Container(
          constraints: BoxConstraints(minHeight: wide ? 260 : 110),
          padding: EdgeInsets.symmetric(horizontal: wide ? 20 : 24, vertical: wide ? 24 : 16),
          decoration: BoxDecoration(color: bg, border: Border.all(color: p.text, width: 3), borderRadius: BorderRadius.circular(28)),
          child: wide
              ? Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Icon(icon, size: 84, color: fg),
                  const SizedBox(height: 14),
                  Text(label, textAlign: TextAlign.center, style: TextStyle(fontSize: 40, height: 1.1, fontWeight: FontWeight.w800, color: fg)),
                  const SizedBox(height: 8),
                  Text(hint, textAlign: TextAlign.center, style: TextStyle(fontSize: 22, color: fg.withValues(alpha: 0.85))),
                ])
              : Row(children: [
                  Icon(icon, size: 52, color: fg),
                  const SizedBox(width: 18),
                  Expanded(child: Text(label, style: TextStyle(fontSize: 28, height: 1.1, fontWeight: FontWeight.w800, color: fg))),
                ]),
        ),
      );
    }

    final buttons = [
      big('Watch TV', 'Opens your last channel', Icons.live_tv_outlined, p.accent, Colors.black, watchTv, autofocus: true),
      big('Movies and shows', 'Pick something to watch', Icons.movie_outlined, p.text, Colors.black,
          () => ShellNav.maybeOf(context)?.select(3)),
      big('Find', 'Type a name', Icons.search, p.bg, p.text, () => ShellNav.maybeOf(context)?.select(5)),
    ];

    return ListView(
      padding: EdgeInsets.fromLTRB(wide ? 40 : 16, wide ? 24 : 16, wide ? 40 : 16, 24),
      children: [
        Text(_greeting, style: TextStyle(fontSize: wide ? 48 : 36, fontWeight: FontWeight.w800, color: p.text)),
        Text('Pick one. Press OK.', style: TextStyle(fontSize: wide ? 26 : 20, color: p.accent)),
        SizedBox(height: wide ? 24 : 16),
        if (wide)
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            for (var i = 0; i < buttons.length; i++) ...[
              if (i > 0) const SizedBox(width: 24),
              Expanded(child: buttons[i]),
            ],
          ])
        else
          for (final b in buttons) Padding(padding: const EdgeInsets.only(bottom: 14), child: b),
        if (resume != null) ...[
          SizedBox(height: wide ? 24 : 6),
          FocusSurface(
            radius: 20,
            semanticLabel: 'Keep watching ${resume.name}',
            onTap: () => openItem(context, resume),
            builder: (_, __) => Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(color: p.surface, border: Border.all(color: p.text, width: 2), borderRadius: BorderRadius.circular(20)),
              child: Row(children: [
                Icon(Icons.play_circle_outline, size: wide ? 44 : 34, color: p.accent),
                const SizedBox(width: 14),
                Expanded(
                    child: Text('Keep watching: ${resume.name}',
                        maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: wide ? 28 : 20, fontWeight: FontWeight.w700, color: p.text))),
              ]),
            ),
          ),
        ],
        SizedBox(height: wide ? 24 : 14),
        Align(
          alignment: Alignment.centerRight,
          child: FocusSurface(
            radius: 16,
            semanticLabel: 'Settings',
            onTap: () => ShellNav.maybeOf(context)?.select(6),
            builder: (_, __) => Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.settings_outlined, color: p.muted, size: 26),
                const SizedBox(width: 8),
                Text('Settings', style: TextStyle(fontSize: 20, color: p.muted)),
              ]),
            ),
          ),
        ),
      ],
    );
  }
}
