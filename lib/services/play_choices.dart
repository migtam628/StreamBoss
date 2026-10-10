/// How to play one title, chosen on its details page (Play options) for this play only. Anything left
/// null follows Settings > Playback.
class PlayChoices {
  /// A language setting such as `es,spa`; '' is automatic.
  final String? audioLang, subLang;
  final bool? subsOn;
  final double? speed;
  const PlayChoices({this.audioLang, this.subLang, this.subsOn, this.speed});

  bool get isEmpty => audioLang == null && subLang == null && subsOn == null && speed == null;

  PlayChoices copyWith({Object? audioLang = _keep, Object? subLang = _keep, Object? subsOn = _keep, Object? speed = _keep}) =>
      PlayChoices(
        audioLang: identical(audioLang, _keep) ? this.audioLang : audioLang as String?,
        subLang: identical(subLang, _keep) ? this.subLang : subLang as String?,
        subsOn: identical(subsOn, _keep) ? this.subsOn : subsOn as bool?,
        speed: identical(speed, _keep) ? this.speed : speed as double?,
      );
}

const _keep = Object();

/// The languages the player can prefer, as (setting value, name). The same ones Settings > Playback offers.
const playLanguages = <(String, String)>[
  ('', 'Automatic'),
  ('en,eng', 'English'),
  ('es,spa', 'Spanish'),
  ('fr,fre,fra', 'French'),
  ('de,ger,deu', 'German'),
  ('pt,por', 'Portuguese'),
  ('it,ita', 'Italian'),
  ('nl,dut,nld', 'Dutch'),
  ('pl,pol', 'Polish'),
  ('tr,tur', 'Turkish'),
  ('ru,rus', 'Russian'),
  ('ar,ara', 'Arabic'),
  ('hi,hin', 'Hindi'),
];

const playSpeeds = <double>[0.75, 1.0, 1.25, 1.5, 2.0];
