import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../layouts/common.dart';
import '../layouts/ui_layout.dart';
import '../services/vod_filter.dart';
import '../state/app_state.dart';
import 'tv.dart';

/// A search field and a Filters button for the Movies, Series and Anime lists. It edits the
/// [AppState.vodFilter] of [list] ('movie', 'series', 'anime'), and each list keeps its own.
class VodFilterBar extends StatefulWidget {
  final String list;

  /// What the lists is called in the field's hint ("Filter movies").
  final String noun;

  /// How many titles are shown after filtering, for the count next to the field.
  final int? shown;
  const VodFilterBar({super.key, required this.list, required this.noun, this.shown});

  @override
  State<VodFilterBar> createState() => _VodFilterBarState();
}

class _VodFilterBarState extends State<VodFilterBar> {
  final _text = TextEditingController();
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    _text.dispose();
    super.dispose();
  }

  void _typed(AppState s, String v) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 200), () {
      if (mounted) s.setVodFilter(widget.list, s.vodFilter(widget.list).copyWith(text: v));
    });
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final p = LayoutPalette.of(context);
    final f = s.vodFilter(widget.list);
    if (_text.text != f.text && !(_debounce?.isActive ?? false)) {
      _text.value = TextEditingValue(text: f.text, selection: TextSelection.collapsed(offset: f.text.length));
    }
    final tv = TvScope.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      child: Row(children: [
        Expanded(
          child: SizedBox(
            height: tv ? 48 : 42,
            child: TextField(
              controller: _text,
              onChanged: (v) => _typed(s, v),
              textInputAction: TextInputAction.search,
              style: TextStyle(color: p.text, fontSize: tv ? 18 : 15),
              decoration: InputDecoration(
                isDense: true,
                filled: true,
                fillColor: p.wash(0.08),
                hintText: 'Filter ${widget.noun}',
                hintStyle: TextStyle(color: p.muted),
                prefixIcon: Icon(Icons.filter_alt_outlined, color: p.muted, size: 20),
                suffixText: widget.shown == null || !f.active ? null : '${widget.shown}',
                suffixStyle: TextStyle(color: p.muted, fontWeight: FontWeight.w700),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide.none),
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        FocusSurface(
          radius: 24,
          semanticLabel: f.count == 0 ? 'Filters' : 'Filters, ${f.count} on',
          onTap: () => showVodFilterSheet(context, widget.list, widget.noun),
          builder: (_, __) => Container(
            padding: EdgeInsets.symmetric(horizontal: tv ? 18 : 14, vertical: tv ? 12 : 10),
            decoration: BoxDecoration(color: f.active ? p.accent : p.wash(0.08), borderRadius: BorderRadius.circular(24)),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.tune, size: 18, color: f.active ? p.onAccent : p.text),
              const SizedBox(width: 6),
              Text(f.count == 0 ? 'Filters' : 'Filters · ${f.count}',
                  style: TextStyle(fontWeight: FontWeight.w700, color: f.active ? p.onAccent : p.text)),
            ]),
          ),
        ),
        if (f.active) ...[
          const SizedBox(width: 6),
          IconButton(
            tooltip: 'Clear filters',
            icon: Icon(Icons.close, color: p.muted),
            onPressed: () => s.setVodFilter(widget.list, VodFilter.none),
          ),
        ],
      ]),
    );
  }
}

/// Rating, year, favorites, not-watched-yet and the order.
Future<void> showVodFilterSheet(BuildContext context, String list, String noun) {
  final p = LayoutPalette.of(context);
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: p.surface,
    constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.85, maxWidth: 680),
    builder: (_) => _VodFilterSheet(list: list, noun: noun),
  );
}

class _VodFilterSheet extends StatelessWidget {
  final String list, noun;
  const _VodFilterSheet({required this.list, required this.noun});

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final p = LayoutPalette.of(context);
    final f = s.vodFilter(list);
    void set(VodFilter n) => s.setVodFilter(list, n);
    final langs = s.languagesFor(list).take(24).toList();

    Widget header(String t) => Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 6),
          child: Text(t, style: TextStyle(fontSize: 13, letterSpacing: 1, fontWeight: FontWeight.w800, color: p.muted)),
        );
    Widget chips(List<Widget> c) =>
        Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: Wrap(spacing: 8, runSpacing: 8, children: c));
    Widget chip(String label, bool on, VoidCallback onTap) => FocusSurface(
          radius: 20,
          semanticLabel: label,
          onTap: onTap,
          builder: (_, __) => Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: on ? p.accent : Colors.transparent,
              border: Border.all(color: on ? p.accent : p.line),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(label,
                style: TextStyle(fontWeight: on ? FontWeight.w800 : FontWeight.w500, color: on ? p.onAccent : p.text)),
          ),
        );

    return SafeArea(
      child: ListView(shrinkWrap: true, padding: const EdgeInsets.only(bottom: 12), children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
          child: Row(children: [
            Expanded(child: Text('Filter $noun', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: p.text))),
            TextButton(onPressed: f.active ? () => set(VodFilter.none) : null, child: const Text('Clear all')),
          ]),
        ),
        header('RATING'),
        chips([
          for (final r in VodFilter.ratingSteps)
            chip(r == 0 ? 'Any rating' : '${r.toInt()}+', f.minRating == r, () => set(f.copyWith(minRating: r))),
        ]),
        header('YEAR (READ FROM THE TITLE)'),
        chips([for (final e in Era.values) chip(e.label, f.era == e, () => set(f.copyWith(era: e)))]),
        if (langs.isNotEmpty) ...[
          header('LANGUAGE (PICK AS MANY AS YOU LIKE)'),
          chips([
            chip('All', f.languages.isEmpty, () => set(f.copyWith(languages: {}))),
            for (final (l, n) in langs) chip('${l.name}  $n', f.languages.contains(l.code), () => set(f.copyWith(languages: f.languages.contains(l.code) ? ({...f.languages}..remove(l.code)) : {...f.languages, l.code}))),
          ]),
        ],
        header('SHOW ONLY'),
        chips([
          chip('Favorites', f.favoritesOnly, () => set(f.copyWith(favoritesOnly: !f.favoritesOnly))),
          chip('Not watched yet', f.unwatchedOnly, () => set(f.copyWith(unwatchedOnly: !f.unwatchedOnly))),
        ]),
        header('ORDER'),
        chips([for (final o in VodSort.values) chip(o.label, f.sort == o, () => set(f.copyWith(sort: o)))]),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 4),
          child: FilledButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Done')),
        ),
      ]),
    );
  }
}
