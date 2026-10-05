import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SettingsState extends ChangeNotifier {
  SharedPreferences? _p;

  String decoder = 'auto'; // auto | software
  int bufferSecs = 20; // low 5 / normal 20 / high 60
  double subSize = 36;
  int subColor = 0xFFFFFFFF;
  bool subBackground = true;
  double speed = 1.0;
  String tmdbKey = '';

  Future<void> init() async {
    final p = _p = await SharedPreferences.getInstance();
    decoder = p.getString('decoder') ?? decoder;
    bufferSecs = p.getInt('bufferSecs') ?? bufferSecs;
    subSize = p.getDouble('subSize') ?? subSize;
    subColor = p.getInt('subColor') ?? subColor;
    subBackground = p.getBool('subBg') ?? subBackground;
    speed = p.getDouble('speed') ?? speed;
    tmdbKey = p.getString('tmdbKey') ?? tmdbKey;
  }

  void update({
    String? decoder,
    int? bufferSecs,
    double? subSize,
    int? subColor,
    bool? subBackground,
    double? speed,
    String? tmdbKey,
  }) {
    this.decoder = decoder ?? this.decoder;
    this.bufferSecs = bufferSecs ?? this.bufferSecs;
    this.subSize = subSize ?? this.subSize;
    this.subColor = subColor ?? this.subColor;
    this.subBackground = subBackground ?? this.subBackground;
    this.speed = speed ?? this.speed;
    this.tmdbKey = tmdbKey ?? this.tmdbKey;
    final p = _p;
    if (p != null) {
      p.setString('decoder', this.decoder);
      p.setInt('bufferSecs', this.bufferSecs);
      p.setDouble('subSize', this.subSize);
      p.setInt('subColor', this.subColor);
      p.setBool('subBg', this.subBackground);
      p.setDouble('speed', this.speed);
      p.setString('tmdbKey', this.tmdbKey);
    }
    notifyListeners();
  }

  Map<String, dynamic> toMap() => {
        'decoder': decoder,
        'bufferSecs': bufferSecs,
        'subSize': subSize,
        'subColor': subColor,
        'subBackground': subBackground,
        'speed': speed,
        'tmdbKey': tmdbKey,
      };

  void applyMap(Map<String, dynamic> m) => update(
        decoder: m['decoder'] as String?,
        bufferSecs: (m['bufferSecs'] as num?)?.toInt(),
        subSize: (m['subSize'] as num?)?.toDouble(),
        subColor: (m['subColor'] as num?)?.toInt(),
        subBackground: m['subBackground'] as bool?,
        speed: (m['speed'] as num?)?.toDouble(),
        tmdbKey: m['tmdbKey'] as String?,
      );
}
