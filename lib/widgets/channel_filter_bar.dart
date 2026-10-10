import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../layouts/common.dart';
import '../layouts/ui_layout.dart';
import '../services/channel_filter.dart';
import '../state/app_state.dart';
import 'tv.dart';

/// A search field and a Filters button for the live channel lists. It edits [AppState.channelFilter],
/// which the Live screens and the Guide share.
class ChannelFilterBar extends StatefulWidget {
  /// How many channels are shown after filtering, for the count next to the field.
  final int? shown;
  const ChannelFilterBar({super.key, this.shown});

  @override
  State<ChannelFilterBar> createState() => _ChannelFilterBarState();
}

class _ChannelFilterBarState extends State<ChannelFilterBar> {
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
      if (mounted) s.setChannelFilter(s.channelFilter.copyWith(text: v));
    });
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final p = LayoutPalette.of(context);
    final f = s.channelFilter;
    // Follow changes made elsewhere (Clear, or the other screen) without fighting what is being typed.
    if (_text.text != f.text && !(_debounce?.isActive ?? false)) {
      _text.value = TextEditingValue(
          text: f.text,
          selection: TextSelection.collapsed(offset: f.text.length));
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
                hintText: 'Filter channels',
                hintStyle: TextStyle(color: p.muted),
                prefixIcon:
                    Icon(Icons.filter_alt_outlined, color: p.muted, size: 20),
                suffixText: widget.shown == null || !f.active
                    ? null
                    : '${widget.shown}',
                suffixStyle:
                    TextStyle(color: p.muted, fontWeight: FontWeight.w700),
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24),
                    borderSide: BorderSide.none),
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        FocusSurface(
          radius: 24,
          semanticLabel: f.count == 0 ? 'Filters' : 'Filters, ${f.count} on',
          onTap: () => showChannelFilterSheet(context),
          builder: (_, __) => Container(
            padding: EdgeInsets.symmetric(
                horizontal: tv ? 18 : 14, vertical: tv ? 12 : 10),
            decoration: BoxDecoration(
              color: f.active ? p.accent : p.wash(0.08),
              borderRadius: BorderRadius.circular(24),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.tune, size: 18, color: f.active ? p.onAccent : p.text),
              const SizedBox(width: 6),
              Text(f.count == 0 ? 'Filters' : 'Filters · ${f.count}',
                  style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: f.active ? p.onAccent : p.text)),
            ]),
          ),
        ),
        if (f.active) ...[
          const SizedBox(width: 6),
          IconButton(
            tooltip: 'Clear filters',
            icon: Icon(Icons.close, color: p.muted),
            onPressed: () => s.setChannelFilter(ChannelFilter.none),
          ),
        ],
      ]),
    );
  }
}

/// The filters that do not fit in the bar: quality, country, favorites, guide data and the order.
Future<void> showChannelFilterSheet(BuildContext context) {
  final p = LayoutPalette.of(context);
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: p.surface,
    constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.85, maxWidth: 680),
    builder: (_) => const _FilterSheet(),
  );
}

class _FilterSheet extends StatelessWidget {
  const _FilterSheet();

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final p = LayoutPalette.of(context);
    final f = s.channelFilter;
    final countries =
        countriesIn(s.shown.live, s.liveCategoryName).take(24).toList();

    Widget header(String t) => Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 6),
          child: Text(t,
              style: TextStyle(
                  fontSize: 13,
                  letterSpacing: 1,
                  fontWeight: FontWeight.w800,
                  color: p.muted)),
        );

    Widget chips(List<Widget> c) => Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Wrap(spacing: 8, runSpacing: 8, children: c),
        );

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
                style: TextStyle(
                    fontWeight: on ? FontWeight.w800 : FontWeight.w500,
                    color: on ? p.onAccent : p.text)),
          ),
        );

    return SafeArea(
      child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.only(bottom: 12),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
              child: Row(children: [
                Expanded(
                    child: Text('Filter channels',
                        style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                            color: p.text))),
                TextButton(
                  onPressed: f.active
                      ? () => s.setChannelFilter(ChannelFilter.none)
                      : null,
                  child: const Text('Clear all'),
                ),
              ]),
            ),
            header('QUALITY'),
            chips([
              for (final q in QualityFilter.values)
                chip(q.label, f.quality == q,
                    () => s.setChannelFilter(f.copyWith(quality: q))),
            ]),
            if (countries.isNotEmpty) ...[
              header('COUNTRY'),
              chips([
                chip('All', f.country == null,
                    () => s.setChannelFilter(f.copyWith(country: null))),
                for (final (c, n) in countries)
                  chip('${c.name}  $n', f.country == c.code,
                      () => s.setChannelFilter(f.copyWith(country: c.code))),
              ]),
            ],
            header('SHOW ONLY'),
            chips([
              chip(
                  'Favorites',
                  f.favoritesOnly,
                  () => s.setChannelFilter(
                      f.copyWith(favoritesOnly: !f.favoritesOnly))),
              chip(
                  'With TV guide',
                  f.guideOnly,
                  () =>
                      s.setChannelFilter(f.copyWith(guideOnly: !f.guideOnly))),
            ]),
            header('ORDER'),
            chips([
              for (final o in ChannelSort.values)
                chip(o.label, f.sort == o,
                    () => s.setChannelFilter(f.copyWith(sort: o))),
            ]),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 4),
              child: FilledButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Done')),
            ),
          ]),
    );
  }
}
