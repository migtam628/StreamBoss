import 'package:flutter/material.dart';
import '../layouts/ui_layout.dart';
import 'package:provider/provider.dart';
import '../services/mpv_props.dart';
import '../services/shaders.dart';
import '../state/settings_state.dart';
import '../theme.dart';
import '../widgets/tv_text_field.dart';

/// Shader library: toggle, drag to reorder (pipeline order), add custom GLSL.
class ShaderScreen extends StatelessWidget {
  const ShaderScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final st = context.watch<SettingsState>();
    final list = st.shaders;

    return Scaffold(
      appBar: AppBar(title: const Text('Shaders'), backgroundColor: LayoutPalette.of(context).bg),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: Boss.accent,
        icon: const Icon(Icons.add),
        label: const Text('Add custom'),
        onPressed: () => _addCustom(context, st),
      ),
      body: !shadersSupported
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text('Shaders need the native player (desktop, Android, iOS). They are not available on web.',
                    textAlign: TextAlign.center),
              ),
            )
          : Column(children: [
              const Padding(
                padding: EdgeInsets.all(16),
                child: Text(
                  'Enabled shaders run top to bottom. Drag to change the order. '
                  'Changes apply to the next video and live in the player\'s Shaders menu.',
                  style: TextStyle(color: Boss.muted),
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
                      subtitle: Text(s.builtin ? s.description : 'Custom'),
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
        title: const Text('Add custom shader'),
        content: SizedBox(
          width: 520,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TvTextField(controller: name, decoration: const InputDecoration(labelText: 'Name')),
            const SizedBox(height: 12),
            TvTextField(
              controller: src,
              minLines: 6,
              maxLines: 12,
              decoration: const InputDecoration(
                labelText: 'mpv GLSL hook source',
                hintText: '//!HOOK LUMA\n//!BIND HOOKED\nvec4 hook() { ... }',
              ),
            ),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Add')),
        ],
      ),
    );
    if (ok != true) return;
    final text = src.text.trim();
    if (!text.contains('//!HOOK') || !text.contains('hook()')) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('That does not look like an mpv hook shader (needs //!HOOK and hook()).')));
      }
      return;
    }
    final id = 'custom_${DateTime.now().millisecondsSinceEpoch}';
    st.setShaders(
      custom: [
        ...st.customShaders,
        ShaderDef(id: id, name: name.text.trim().isEmpty ? 'Custom shader' : name.text.trim(), source: text),
      ],
    );
  }
}
