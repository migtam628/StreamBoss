import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../layouts/common.dart';
import '../layouts/ui_layout.dart';
import '../models/media.dart';
import '../services/details_logic.dart';
import '../services/play_choices.dart';
import '../state/settings_state.dart';

/// What the Play options sheet decided: which copy, where to start and how to play it.
class PlayRequest {
  final MediaItem item;
  final Duration? startAt;
  final PlayChoices choices;
  const PlayRequest(this.item, this.startAt, this.choices);
}

String clock(Duration d) {
  final h = d.inHours, m = d.inMinutes % 60, s = d.inSeconds % 60;
  String two(int v) => v.toString().padLeft(2, '0');
  return h > 0 ? '$h:${two(m)}:${two(s)}' : '$m:${two(s)}';
}

/// Sets up one play: Resume or From the beginning, which copy of the title, audio and subtitle
/// language, and speed. Nothing here changes Settings; it is for this play only.
Future<PlayRequest?> showPlayOptions(
  BuildContext context, {
  required MediaItem item,
  Duration? resume,
  List<MediaItem> versions = const [],
}) {
  final p = LayoutPalette.of(context);
  return showModalBottomSheet<PlayRequest>(
    context: context,
    isScrollControlled: true,
    backgroundColor: p.surface,
    constraints: BoxConstraints(maxWidth: 680, maxHeight: MediaQuery.sizeOf(context).height * 0.9),
    builder: (_) => _PlayOptions(item: item, resume: resume, versions: versions),
  );
}

class _PlayOptions extends StatefulWidget {
  final MediaItem item;
  final Duration? resume;
  final List<MediaItem> versions;
  const _PlayOptions({required this.item, required this.resume, required this.versions});

  @override
  State<_PlayOptions> createState() => _PlayOptionsState();
}

class _PlayOptionsState extends State<_PlayOptions> {
  late MediaItem _item = widget.item;
  late bool _fromResume = widget.resume != null;
  String? _audio; // null = as in Settings
  String? _subs; // null = as in Settings, 'off' = none, else a language setting
  double? _speed;

  @override
  Widget build(BuildContext context) {
    final p = LayoutPalette.of(context);
    final st = context.watch<SettingsState>();

    Widget head(String t) => Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 6),
          child: Text(t, style: TextStyle(fontSize: 12, letterSpacing: 1.1, fontWeight: FontWeight.w800, color: p.muted)),
        );
    Widget chips(List<(String, bool, VoidCallback)> c) => Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Wrap(spacing: 8, runSpacing: 8, children: [
            for (final (label, on, tap) in c)
              FocusSurface(
                radius: 20,
                semanticLabel: label,
                onTap: tap,
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
              ),
          ]),
        );

    final all = [widget.item, ...widget.versions];
    final choices = PlayChoices(
      audioLang: _audio,
      subLang: _subs == null || _subs == 'off' ? null : _subs,
      subsOn: _subs == null ? null : _subs != 'off',
      speed: _speed,
    );
    final resuming = _fromResume && widget.resume != null && identical(_item, widget.item);

    return SafeArea(
      child: ListView(shrinkWrap: true, padding: const EdgeInsets.only(bottom: 12), children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
          child: Text('Play options', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: p.text)),
        ),
        if (widget.resume != null) ...[
          head('START'),
          chips([
            ('Resume ${clock(widget.resume!)}', _fromResume, () => setState(() => _fromResume = true)),
            ('From the beginning', !_fromResume, () => setState(() => _fromResume = false)),
          ]),
        ],
        if (all.length > 1) ...[
          head('COPY'),
          chips([
            for (final v in all)
              (qualityTagOf(v.name) ?? (identical(v, widget.item) ? 'This one' : 'Other copy'), identical(v, _item),
                  () => setState(() => _item = v)),
          ]),
        ],
        head('AUDIO'),
        chips([
          ('As in Settings', _audio == null, () => setState(() => _audio = null)),
          for (final (code, name) in playLanguages.skip(1)) (name, _audio == code, () => setState(() => _audio = code)),
        ]),
        head('SUBTITLES'),
        chips([
          ('As in Settings', _subs == null, () => setState(() => _subs = null)),
          ('Off', _subs == 'off', () => setState(() => _subs = 'off')),
          for (final (code, name) in playLanguages.skip(1)) (name, _subs == code, () => setState(() => _subs = code)),
        ]),
        head('SPEED'),
        chips([
          ('As in Settings (${st.speed}×)', _speed == null, () => setState(() => _speed = null)),
          for (final s in playSpeeds) ('$s×', _speed == s, () => setState(() => _speed = s)),
        ]),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 4),
          child: FilledButton.icon(
            autofocus: true,
            icon: const Icon(Icons.play_arrow),
            label: Text(resuming ? 'Resume' : 'Play'),
            onPressed: () => Navigator.pop(context, PlayRequest(_item, resuming ? widget.resume : null, choices)),
          ),
        ),
      ]),
    );
  }
}
