import 'package:flutter/material.dart';
import '../layouts/ui_layout.dart';
import 'package:provider/provider.dart';
import '../services/mpv_props.dart';
import '../services/shaders.dart';
import '../state/settings_state.dart';
import '../theme.dart';
import '../widgets/tv_text_field.dart';
import '../l10n/l10n.dart';

/// Shader library: toggle, drag to reorder (pipeline order), add custom GLSL.
class ShaderScreen extends StatelessWidget {
  const ShaderScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final st = context.watch<SettingsState>();
    final list = st.shaders;

    return Scaffold(
      appBar: AppBar(title: Text(tr('Shaders')), backgroundColor: LayoutPalette.of(context).bg),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: Boss.accent,
        icon: const Icon(Icons.add),
        label: Text(tr('Add custom')),
        onPressed: () => _addCustom(context, st),
      ),
      body: !shadersSupported
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(tr('Shaders need the native player (desktop, Android, iOS). They are not available on web.'),
                    textAlign: TextAlign.center),
              ),
            )
          : Column(children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  tr('Enabled shaders run top to bottom. Drag to change the order. '
                  'Changes apply to the next video and live in the player\'s Shaders menu.'),
                  style: const TextStyle(color: Boss.muted),
                ),
              ),
              Expanded(
                child: ReorderableListView.builder(
                  itemCount: list.length,
                  onReorderItem: (a, b) {
                    final ids = [for (final s in list) s.id];
                    ids.insert(b, ids.removeAt(a));
                    st.setShaders(order: ids);
                  },
                  itemBuilder: (_, i) {
                    final s = list[i];
                    return ListTile(
                      key: ValueKey(s.id),
                      leading: ReorderableDragStartListener(
                        index: i,
                        child: const Icon(Icons.drag_handle),
                      ),
                      title: Text(s.name),
                      subtitle: Text(s.builtin ? s.description : tr('Custom')),
                      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                        if (!s.builtin)
                          IconButton(
                            icon: const Icon(Icons.delete_outline),
                            onPressed: () => st.setShaders(
                              custom: [for (final c in st.customShaders) if (c.id != s.id) c],
                              enabled: {...st.shaderEnabled}..remove(s.id),
                            ),
                          ),
                        Switch(
                          value: st.shaderEnabled.contains(s.id),
                          activeThumbColor: Boss.accent,
                          onChanged: (v) => st.setShaders(
                            enabled: v
                                ? {...st.shaderEnabled, s.id}
                                : ({...st.shaderEnabled}..remove(s.id)),
                          ),
                        ),
                      ]),
                    );
                  },
                ),
              ),
            ]),
    );
  }

  Future<void> _addCustom(BuildContext context, SettingsState st) async {
    final name = TextEditingController();
    final src = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('Add custom shader')),
        content: SizedBox(
          width: 520,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TvTextField(controller: name, decoration: InputDecoration(labelText: tr('Name'))),
            const SizedBox(height: 12),
            TvTextField(
              controller: src,
              minLines: 6,
              maxLines: 12,
              decoration: InputDecoration(
                labelText: tr('mpv GLSL hook source'),
                hintText: tr('//!HOOK LUMA\n//!BIND HOOKED\nvec4 hook() { ... }'),
              ),
            ),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('Cancel'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(tr('Add'))),
        ],
      ),
    );
    if (ok != true) return;
    final text = src.text.trim();
    if (!text.contains('//!HOOK') || !text.contains('hook()')) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(tr('That does not look like an mpv hook shader (needs //!HOOK and hook()).'))));
      }
      return;
    }
    final id = 'custom_${DateTime.now().millisecondsSinceEpoch}';
    st.setShaders(
      custom: [
        ...st.customShaders,
        ShaderDef(id: id, name: name.text.trim().isEmpty ? tr('Custom shader') : name.text.trim(), source: text),
      ],
    );
  }
}
