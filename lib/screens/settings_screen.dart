import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../state/profiles_state.dart';
import '../widgets/pin_dialog.dart';
import 'profile_picker_screen.dart';
import '../layouts/common.dart';
import '../layouts/ui_layout.dart';
import 'settings/settings_pages.dart';

/// Settings hub. Wide windows get a two-pane layout (sections on the left, the page on the
/// right); narrow ones get a list that opens each section as its own page.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  int _sel = 0;
  Timer? _relock;

  @override
  void dispose() {
    _relock?.cancel();
    super.dispose();
  }

  /// Shuts Settings again once the time after the PIN runs out, even if nothing else rebuilds.
  void _watchLock(ProfilesState ps) {
    _relock?.cancel();
    if (ps.hasPin && ps.current.kids && !ps.settingsLocked) {
      _relock = Timer(ProfilesState.settingsWindow + const Duration(seconds: 1), () {
        if (mounted) setState(() {});
      });
    }
  }

  Widget _tile(int i, {required bool wide}) {
    final sec = settingsSections[i];
    return ListTile(
      selected: wide && i == _sel,
      selectedColor: LayoutPalette.of(context).accent,
      selectedTileColor: LayoutPalette.of(context).accent.withValues(alpha: 0.12),
      leading: Icon(sec.icon),
      title: Text(sec.title),
      subtitle: Text(sec.subtitle),
      trailing: wide ? null : const Icon(Icons.chevron_right),
      // Moving focus with a D-pad previews the page, so no extra OK press is needed on TV.
      onFocusChange: wide
          ? (f) {
              if (f && _sel != i) setState(() => _sel = i);
            }
          : null,
      onTap: () {
        if (wide) {
          setState(() => _sel = i);
        } else {
          Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => Scaffold(
              appBar: AppBar(title: Text(sec.title), backgroundColor: LayoutPalette.of(context).bg),
              body: sec.builder(context),
            ),
          ));
        }
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final ps = Provider.of<ProfilesState?>(context);
    if (ps != null) {
      if (ps.settingsLocked) return _Locked(ps);
      _watchLock(ps);
    }
    return LayoutBuilder(builder: (context, c) {
      final wide = c.maxWidth >= 860;
      final own = ps != null && ps.current.ownSettings;
      final header = Padding(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Settings', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800)),
          if (own)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text('Layout, text, language, subtitle and filter changes apply to ${ps.current.name} only.',
                  style: TextStyle(color: LayoutPalette.of(context).accent2, fontSize: 13)),
            ),
        ]),
      );
      final list = ListView(children: [
        header,
        for (var i = 0; i < settingsSections.length; i++) _tile(i, wide: wide),
      ]);
      if (!wide) return SafeArea(child: list);
      return Row(children: [
        SizedBox(width: 320, child: list),
        const VerticalDivider(width: 1),
        Expanded(child: KeyedSubtree(key: ValueKey(_sel), child: settingsSections[_sel].builder(context))),
      ]);
    });
  }
}

/// Shown instead of Settings while a Kids profile with a PIN is in use.
class _Locked extends StatelessWidget {
  final ProfilesState ps;
  const _Locked(this.ps);

  @override
  Widget build(BuildContext context) {
    final p = LayoutPalette.of(context);
    Widget button(String label, IconData icon, VoidCallback onTap, {bool autofocus = false}) => FocusSurface(
          radius: 26,
          autofocus: autofocus,
          semanticLabel: label,
          onTap: onTap,
          builder: (_, __) => Container(
            padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
            color: autofocus ? p.accent : p.wash(),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(icon, color: autofocus ? p.onAccent : p.text),
              const SizedBox(width: 10),
              Text(label, style: TextStyle(fontWeight: FontWeight.w700, color: autofocus ? p.onAccent : p.text)),
            ]),
          ),
        );
    return Center(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.lock_outline, size: 56, color: p.muted),
        const SizedBox(height: 14),
        const Text('Settings are locked', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800)),
        const SizedBox(height: 6),
        Text('This is a Kids profile. Enter the PIN to change anything.', style: TextStyle(color: p.muted)),
        const SizedBox(height: 22),
        Wrap(spacing: 12, runSpacing: 12, alignment: WrapAlignment.center, children: [
          button('Enter PIN', Icons.pin_outlined, () async {
            if (await askPin(context, ps)) ps.openSettings();
          }, autofocus: true),
          button("Who's watching?", Icons.switch_account_outlined,
              () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ProfilePickerScreen()))),
        ]),
      ]),
    );
  }
}
