import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/media.dart';
import '../screens/guide_screen.dart';
import '../screens/open_item.dart';
import '../services/time_format.dart';
import '../services/xmltv.dart';
import '../state/app_state.dart';
import '../state/settings_state.dart';
import '../widgets/live_preview.dart';
import '../widgets/net_image.dart';
import '../widgets/tv.dart';
import 'common.dart';
import 'ui_layout.dart';

/// Prime Time's Home: the guide, with the highlighted programme's details above it.
class PrimeHome extends StatefulWidget {
  const PrimeHome({super.key});

  @override
  State<PrimeHome> createState() => _PrimeHomeState();
}

class _PrimeHomeState extends State<PrimeHome> {
  MediaItem? _channel;
  Programme? _prog;

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      _PrimeHeader(channel: _channel, programme: _prog),
      Expanded(
        child: GuideScreen(
          onFocusProgramme: (c, p) {
            if (_channel != c || _prog != p) {
              setState(() {
                _channel = c;
                _prog = p;
              });
            }
          },
        ),
      ),
    ]);
  }
}

class _PrimeHeader extends StatelessWidget {
  final MediaItem? channel;
  final Programme? programme;
  const _PrimeHeader({this.channel, this.programme});

  String _when(Programme p, bool use24h) {
    final now = DateTime.now();
    final span =
        '${fmtTime(p.start, use24h: use24h)} – ${fmtTime(p.end, use24h: use24h)}';
    if (p.isNow) {
      final m = p.end.difference(now).inMinutes;
      return '$span · ${m >= 60 ? '${m ~/ 60}h ${m % 60}m' : '$m min'} left';
    }
    if (p.start.isAfter(now)) {
      final m = p.start.difference(now).inMinutes;
      return '$span · starts in ${m >= 60 ? '${m ~/ 60}h ${m % 60}m' : '$m min'}';
    }
    return '$span · ended';
  }

  @override
  Widget build(BuildContext context) {
    final p = LayoutPalette.of(context);
    final tv = TvScope.of(context);
    final wide = tv || MediaQuery.sizeOf(context).width >= 800;
    final use24h = context.select<SettingsState, bool>((s) => s.use24h);
    final live = context.read<AppState>().shown.live;
    final ch = channel;
    final prog = programme;
    final h = (ch == null || prog == null) ? 48.0 : (wide ? 150.0 : 96.0);
    return Container(
      height: h,
      padding: EdgeInsets.fromLTRB(wide ? 20 : 12, 8, wide ? 20 : 12, 8),
      child: ch == null || prog == null
          ? Align(
              alignment: Alignment.centerLeft,
              child: Text('Move over the grid to see what is on.',
                  style: TextStyle(color: p.muted, fontSize: wide ? 18 : 14)),
            )
          : Row(children: [
              AspectRatio(
                aspectRatio: 16 / 9,
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(10),
                    gradient: LinearGradient(
                        colors: [p.surfaceHi, p.bg],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: Stack(fit: StackFit.expand, children: [
                    // What is on now plays here a moment after the cursor lands on it; the logo shows until then.
                    if (prog.isNow)
                      LivePreview(
                        key: ValueKey(ch.key),
                        channel: ch,
                        fallback: ch.poster == null
                            ? const SizedBox.shrink()
                            : Padding(
                                padding: const EdgeInsets.all(14),
                                child: NetImage(ch.poster!,
                                    fit: BoxFit.contain,
                                    fallback: () => const SizedBox.shrink())),
                      )
                    else if (ch.poster != null)
                      Padding(
                          padding: const EdgeInsets.all(14),
                          child: NetImage(ch.poster!,
                              fit: BoxFit.contain,
                              fallback: () => const SizedBox.shrink())),
                    if (prog.isNow)
                      Positioned(
                        left: 6,
                        top: 6,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 1),
                          decoration: BoxDecoration(
                              color: const Color(0xFFE5484D),
                              borderRadius: BorderRadius.circular(4)),
                          child: const Text('LIVE',
                              style: TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 11,
                                  letterSpacing: 1)),
                        ),
                      ),
                  ]),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Eyebrow(ch.name, color: p.accent2),
                      const SizedBox(height: 2),
                      Text(prog.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: wide ? 30 : 20,
                              fontWeight: FontWeight.w800,
                              height: 1.05)),
                      const SizedBox(height: 4),
                      Text(_when(prog, use24h),
                          style: TextStyle(
                              color: p.text.withValues(alpha: 0.8),
                              fontSize: wide ? 16 : 13)),
                      if (wide) ...[
                        const SizedBox(height: 8),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: FilledButton(
                              onPressed: () =>
                                  openItem(context, ch, queue: live),
                              child: const Text('Watch channel')),
                        ),
                      ],
                    ]),
              ),
            ]),
    );
  }
}
