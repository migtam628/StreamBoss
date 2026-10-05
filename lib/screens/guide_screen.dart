import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/media.dart';
import '../services/xtream_client.dart';
import '../state/app_state.dart';
import '../theme.dart';
import 'open_item.dart';

/// Channel list with now/next, loaded lazily per visible row (Xtream sources only).
class GuideScreen extends StatefulWidget {
  const GuideScreen({super.key});

  @override
  State<GuideScreen> createState() => _GuideScreenState();
}

class _GuideScreenState extends State<GuideScreen> {
  String? _cat;
  final _cache = <String, Future<List<EpgEntry>>>{};

  String _hm(DateTime d) =>
      '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final cats = s.catalog.liveCategories;
    final all = s.catalog.live;
    final items = _cat == null ? all : all.where((i) => i.categoryId == _cat).toList();
    if (all.isEmpty) {
      return const Center(child: Text('No live channels.', style: TextStyle(color: Boss.muted)));
    }
    return Column(children: [
      SizedBox(
        height: 56,
        child: ListView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          children: [
            for (final c in [const Category('', 'All'), ...cats])
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ChoiceChip(
                  label: Text(c.name),
                  selected: (_cat ?? '') == c.id,
                  selectedColor: Boss.accent,
                  onSelected: (_) => setState(() => _cat = c.id.isEmpty ? null : c.id),
                ),
              ),
          ],
        ),
      ),
      Expanded(
        child: ListView.builder(
          itemCount: items.length,
          itemBuilder: (_, i) {
            final ch = items[i];
            final fut = _cache.putIfAbsent(ch.id, () => s.epg(ch).catchError((_) => <EpgEntry>[]));
            return ListTile(
              leading: const Icon(Icons.live_tv, color: Boss.muted),
              title: Text(ch.name, maxLines: 1, overflow: TextOverflow.ellipsis),
              subtitle: FutureBuilder<List<EpgEntry>>(
                future: fut,
                builder: (_, snap) {
                  final list = snap.data ?? const [];
                  final now = list.where((e) => e.isNow).firstOrNull;
                  final next = list.where((e) => e.start.isAfter(DateTime.now())).firstOrNull;
                  if (now == null) {
                    return Text(snap.connectionState == ConnectionState.done ? 'No guide data' : '…',
                        style: const TextStyle(color: Boss.muted));
                  }
                  return Text(
                    '${_hm(now.start)}–${_hm(now.end)}  ${now.title}'
                    '${next != null ? '\nNext ${_hm(next.start)}  ${next.title}' : ''}',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  );
                },
              ),
              onTap: () => openItem(context, ch, queue: items),
            );
          },
        ),
      ),
    ]);
  }
}
