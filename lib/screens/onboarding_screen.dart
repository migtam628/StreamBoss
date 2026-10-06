import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../layouts/common.dart';
import '../layouts/layout_picker.dart';
import '../layouts/ui_layout.dart';
import '../state/settings_state.dart';
import '../widgets/tv.dart';

/// First-run setup: a few short steps (what this app is, the screen, the look, playback, connecting
/// a provider), every choice applied as soon as it is made. Skippable at any point. [onDone] runs on
/// the last step or Skip; the app uses it to remember that setup happened.
class OnboardingScreen extends StatefulWidget {
  final VoidCallback onDone;

  /// True when opened again from Settings: the last button then says Done instead of Connect.
  final bool rerun;
  const OnboardingScreen({super.key, required this.onDone, this.rerun = false});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  static const _titles = [
    'Welcome',
    'Your screen',
    'Pick a look',
    'Playback',
    'Connect your provider'
  ];
  int _step = 0;

  void _next() {
    if (_step == _titles.length - 1) {
      widget.onDone();
    } else {
      setState(() => _step++);
    }
  }

  void _back() => setState(() => _step--);

  @override
  Widget build(BuildContext context) {
    final p = LayoutPalette.of(context);
    final tv = TvScope.of(context);
    final last = _step == _titles.length - 1;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: tv ? 960 : 760),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 16),
              child: Column(children: [
                Row(children: [
                  Text('STREAMBOSS',
                      style: TextStyle(
                          color: p.accent,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 3,
                          fontSize: 18)),
                  const Spacer(),
                  Text('Step ${_step + 1} of ${_titles.length}',
                      style: TextStyle(color: p.muted)),
                  const SizedBox(width: 12),
                  TextButton(
                      onPressed: widget.onDone,
                      child: const Text('Skip setup')),
                ]),
                const SizedBox(height: 4),
                LinearProgressIndicator(
                  value: (_step + 1) / _titles.length,
                  minHeight: 4,
                  borderRadius: BorderRadius.circular(4),
                  backgroundColor: p.wash(0.12),
                  valueColor: AlwaysStoppedAnimation(p.accent),
                ),
                const SizedBox(height: 20),
                Expanded(
                  child: SingleChildScrollView(
                    key: ValueKey('onb-$_step'),
                    child: Align(
                      alignment: Alignment.topLeft,
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(_titles[_step],
                                style: TextStyle(
                                    fontSize: tv ? 40 : 30,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: -0.5)),
                            const SizedBox(height: 14),
                            _body(context),
                          ]),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Row(children: [
                  if (_step > 0)
                    TextButton(onPressed: _back, child: const Text('Back')),
                  const Spacer(),
                  FilledButton(
                    key: ValueKey('onb-next-$_step'),
                    autofocus: true,
                    onPressed: _next,
                    child: Text(last
                        ? (widget.rerun ? 'Done' : 'Connect my provider')
                        : 'Next'),
                  ),
                ]),
              ]),
            ),
          ),
        ),
      ),
    );
  }

  Widget _body(BuildContext context) {
    final st = context.watch<SettingsState>();
    final p = LayoutPalette.of(context);
    final muted = TextStyle(color: p.muted, fontSize: 16, height: 1.45);
    switch (_step) {
      case 0:
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(
              'StreamBoss plays video from a provider you already have. It does not supply any channels, movies or subscriptions itself.',
              style: muted.copyWith(color: p.text, fontSize: 18)),
          const SizedBox(height: 16),
          _point(p, Icons.dns_outlined, 'Bring your own provider',
              'An Xtream login (server, username, password) or an M3U playlist link.'),
          _point(p, Icons.tune, 'Set it up your way',
              'A couple of quick choices about your screen and how the app looks.'),
          _point(p, Icons.settings_backup_restore, 'Change anything later',
              'Everything here lives in Settings. Skip setup if you like.'),
        ]);
      case 1:
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(
            SettingsState.detectedTv
                ? 'This device looks like a TV.'
                : 'This device looks like a phone, tablet or computer.',
            style: muted.copyWith(color: p.text, fontSize: 18),
          ),
          const SizedBox(height: 14),
          const _Label('Screen type'),
          _Choices<String>(
            value: st.tvMode,
            options: const [
              ('auto', 'Automatic'),
              ('on', 'TV'),
              ('off', 'Phone or computer')
            ],
            onPick: (v) => st.set('tvMode', v),
          ),
          Padding(
              padding: const EdgeInsets.only(top: 6, bottom: 16),
              child: Text(
                  'TV mode lays the screen out for a remote: a bold focus outline and safe margins.',
                  style: muted)),
          const _Label('Text size'),
          _Choices<double>(
            value: st.uiScale,
            options: const [
              (0.85, 'Small'),
              (1.0, 'Normal'),
              (1.15, 'Large'),
              (1.3, 'Extra large')
            ],
            onPick: (v) => st.set('uiScale', v),
          ),
          if (st.isTv) ...[
            const SizedBox(height: 16),
            const _Label('How much fits on the TV'),
            _Choices<int>(
              value: st.tvWidth,
              options: const [
                (1120, 'Larger'),
                (1280, 'Standard'),
                (1440, 'Smaller'),
                (1600, 'Smallest')
              ],
              onPick: (v) => st.set('tvWidth', v),
            ),
            Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                    'Pick the size where everything is easy to read from your seat.',
                    style: muted)),
          ],
        ]);
      case 2:
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(
              'Choose how StreamBoss is laid out. The colors change right away.',
              style: muted.copyWith(color: p.text, fontSize: 18)),
          const SizedBox(height: 10),
          const LayoutPicker(),
          Text('You can switch any time in Settings > Appearance > Layout.',
              style: muted),
        ]);
      case 3:
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('A few playback defaults.',
              style: muted.copyWith(color: p.text, fontSize: 18)),
          const SizedBox(height: 14),
          const _Label('Preferred audio language'),
          _Choices<String>(
            value: st.audioLang,
            options: const [
              ('', 'Automatic'),
              ('en,eng', 'English'),
              ('es,spa', 'Spanish'),
              ('fr,fre,fra', 'French'),
              ('de,ger,deu', 'German'),
              ('pt,por', 'Portuguese')
            ],
            onPick: (v) => st.set('audioLang', v),
          ),
          const SizedBox(height: 16),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Show subtitles automatically'),
            subtitle: Text('When a video has them', style: muted),
            value: st.subsOn,
            activeThumbColor: p.accent,
            onChanged: (v) => st.set('subsOn', v),
          ),
          Text('More playback options are in Settings > Playback.',
              style: muted),
        ]);
      default:
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(
            widget.rerun
                ? 'You are all set. Your provider and everything else stay as they are.'
                : 'Last step: add your provider. Have one of these ready:',
            style: muted.copyWith(color: p.text, fontSize: 18),
          ),
          if (!widget.rerun) ...[
            const SizedBox(height: 14),
            _point(p, Icons.badge_outlined, 'Xtream login',
                'Server address, username and password, as your provider gave them.'),
            _point(p, Icons.link, 'M3U link',
                'A playlist address. Links that contain a username and password work too.'),
            _point(p, Icons.phone_android, 'No typing on a TV',
                'The next screen can show a QR code so you can enter the details from your phone.'),
            _point(p, Icons.public, 'No provider yet?',
                'The next screen also lets you browse free public channels, or try the demo.'),
          ],
        ]);
    }
  }

  Widget _point(LayoutPalette p, IconData icon, String title, String body) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon, color: p.accent, size: 26),
          const SizedBox(width: 14),
          Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title,
                  style: const TextStyle(
                      fontWeight: FontWeight.w700, fontSize: 17)),
              Text(body,
                  style: TextStyle(color: p.muted, fontSize: 15, height: 1.35)),
            ]),
          ),
        ]),
      );
}

class _Label extends StatelessWidget {
  final String text;
  const _Label(this.text);

  @override
  Widget build(BuildContext context) =>
      Padding(padding: const EdgeInsets.only(bottom: 8), child: Eyebrow(text));
}

/// A wrap of focusable choices, one selected.
class _Choices<T> extends StatelessWidget {
  final T value;
  final List<(T, String)> options;
  final ValueChanged<T> onPick;
  const _Choices(
      {required this.value, required this.options, required this.onPick});

  @override
  Widget build(BuildContext context) {
    final p = LayoutPalette.of(context);
    return Wrap(spacing: 10, runSpacing: 10, children: [
      for (final o in options)
        FocusSurface(
          radius: 22,
          semanticLabel: o.$2,
          onTap: () => onPick(o.$1),
          builder: (_, __) {
            final on = o.$1 == value;
            return Container(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 11),
              color: on ? p.accent : p.wash(),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                if (on) ...[
                  Icon(Icons.check, size: 18, color: p.onAccent),
                  const SizedBox(width: 6)
                ],
                Text(o.$2,
                    style: TextStyle(
                        fontWeight: on ? FontWeight.w700 : FontWeight.w500,
                        color: on ? p.onAccent : p.text)),
              ]),
            );
          },
        ),
    ]);
  }
}
