import 'package:flutter/material.dart';
import '../theme.dart';
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

  Widget _tile(int i, {required bool wide}) {
    final sec = settingsSections[i];
    return ListTile(
      selected: wide && i == _sel,
      selectedColor: Boss.accent,
      selectedTileColor: Boss.accent.withValues(alpha: 0.12),
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
              appBar: AppBar(title: Text(sec.title), backgroundColor: Boss.bg),
              body: sec.builder(context),
            ),
          ));
        }
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      final wide = c.maxWidth >= 860;
      const header = Padding(
        padding: EdgeInsets.fromLTRB(16, 20, 16, 8),
        child: Text('Settings', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800)),
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
