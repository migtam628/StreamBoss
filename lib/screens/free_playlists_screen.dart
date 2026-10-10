import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../layouts/common.dart';
import '../layouts/ui_layout.dart';
import '../models/media.dart';
import '../services/free_playlists.dart';
import '../state/app_state.dart';
import '../widgets/tv_text_field.dart';

/// Browse the public playlist directories and add one, several or a whole group as a single source.
/// [loadCountries] is replaceable so tests need no network.
class FreePlaylistsScreen extends StatefulWidget {
  final Future<List<FreeList>> Function()? loadCountries;
  const FreePlaylistsScreen({super.key, this.loadCountries});

  @override
  State<FreePlaylistsScreen> createState() => _FreePlaylistsScreenState();
}

class _FreePlaylistsScreenState extends State<FreePlaylistsScreen> {
  static const _tabs = ['Categories', 'Countries', 'Languages', 'More'];
  int _tab = 0;
  String _q = '';
  final _picked = <String, FreeList>{};
  late final Future<List<FreeList>> _countries =
      (widget.loadCountries ?? loadFreeCountries)();

  List<FreeList> _visible(List<FreeList> all) {
    final q = _q.trim().toLowerCase();
    return q.isEmpty
        ? all
        : all.where((e) => e.name.toLowerCase().contains(q)).toList();
  }

  void _toggle(FreeList l, bool on) =>
      setState(() => on ? _picked[l.id] = l : _picked.remove(l.id));

  void _all(List<FreeList> items, bool on) => setState(() {
        for (final l in items) {
          on ? _picked[l.id] = l : _picked.remove(l.id);
        }
      });

  Future<void> _add() async {
    final picked = _picked.values.toList();
    final heavy = picked.any((e) => e.large) || picked.length > 12;
    if (heavy) {
      final go = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('This may take a while'),
          content: Text(
              '${picked.length} lists will be downloaded and combined. On a phone or a TV stick that can take a minute or more, and the library will be big.'),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel')),
            FilledButton(
                autofocus: true,
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Add anyway')),
          ],
        ),
      );
      if (go != true || !mounted) return;
    }
    final app = context.read<AppState>();
    final nav = Navigator.of(context);
    app.addSource(Source(
        name: freeSourceName(picked),
        type: SourceType.m3u,
        url: picked.map((e) => e.url).join('\n')));
    nav.pop();
  }

  @override
  Widget build(BuildContext context) {
    final p = LayoutPalette.of(context);
    return Scaffold(
      appBar: AppBar(
          title: const Text('Free public channels'), backgroundColor: p.bg),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
                color: p.surface, borderRadius: BorderRadius.circular(12)),
            child: Text(
              'These are public lists of free and publicly available channels kept by third parties (iptv-org and Free-TV). '
              'StreamBoss does not host them or check them. Some channels are offline or only work in some countries, and what you '
              'may watch depends on where you live. Tick the lists you want; they are combined into one library.',
              style: TextStyle(color: p.muted, fontSize: 14, height: 1.35),
            ),
          ),
        ),
        ChipRow(
            labels: _tabs,
            selected: _tab,
            onSelect: (i) => setState(() => _tab = i)),
        Expanded(
            child: _tab == 1
                ? _countriesTab()
                : _listTab(switch (_tab) {
                    0 => freeCategories,
                    2 => freeLanguages,
                    _ => freeCollections
                  })),
        SafeArea(
          top: false,
          child: Container(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            decoration: BoxDecoration(
                color: p.surface,
                border: Border(top: BorderSide(color: p.line))),
            child: Row(children: [
              Expanded(
                  child: Text(
                      _picked.isEmpty
                          ? 'Nothing selected'
                          : '${_picked.length} selected',
                      style: TextStyle(color: p.muted))),
              if (_picked.isNotEmpty)
                TextButton(
                    onPressed: () => setState(_picked.clear),
                    child: const Text('Clear')),
              const SizedBox(width: 8),
              FilledButton(
                  onPressed: _picked.isEmpty ? null : _add,
                  child: Text(_picked.length <= 1
                      ? 'Add'
                      : 'Add ${_picked.length} lists')),
            ]),
          ),
        ),
      ]),
    );
  }

  Widget _countriesTab() => FutureBuilder<List<FreeList>>(
        future: _countries,
        builder: (context, snap) {
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          return _listTab(snap.data!, searchable: true);
        },
      );

  Widget _listTab(List<FreeList> all, {bool searchable = false}) {
    final shown = _visible(all);
    final allOn =
        shown.isNotEmpty && shown.every((e) => _picked.containsKey(e.id));
    return Column(children: [
      if (searchable)
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
          child: TvTextField(
              decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search), hintText: 'Search countries'),
              onChanged: (v) => setState(() => _q = v)),
        ),
      CheckboxListTile(
        dense: true,
        title: Text(
            allOn
                ? 'Clear all ${shown.length} shown'
                : 'Select all ${shown.length} shown',
            style: const TextStyle(fontWeight: FontWeight.w700)),
        value: allOn,
        onChanged: shown.isEmpty ? null : (v) => _all(shown, v ?? false),
      ),
      Expanded(
        child: ListView.builder(
          itemCount: shown.length,
          itemBuilder: (_, i) {
            final l = shown[i];
            return CheckboxListTile(
              title: Text(l.name),
              subtitle:
                  Text(l.blurb, maxLines: 2, overflow: TextOverflow.ellipsis),
              value: _picked.containsKey(l.id),
              onChanged: (v) => _toggle(l, v ?? false),
            );
          },
        ),
      ),
    ]);
  }
}
