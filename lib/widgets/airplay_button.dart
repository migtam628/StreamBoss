import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_to_airplay/flutter_to_airplay.dart';
import '../theme.dart';

/// AirPlay is only on iPhone and iPad: this is false everywhere else, and the button draws nothing.
bool get airPlaySupported => !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

/// The system's AirPlay button. It opens the system list of speakers and TVs; what is played is sent
/// to the one picked. The player plays through libmpv, which sends its sound over AirPlay; the picture
/// follows only if the system mirrors the screen (Control Center > Screen Mirroring).
class AirPlayButton extends StatelessWidget {
  const AirPlayButton({super.key});

  @override
  Widget build(BuildContext context) {
    if (!airPlaySupported) return const SizedBox.shrink();
    return const SizedBox(
      width: 52,
      height: 52,
      child: AirPlayRoutePickerView(
        tintColor: Colors.white,
        activeTintColor: Boss.accent,
        backgroundColor: Colors.transparent,
        prioritizesVideoDevices: true,
        width: 52,
        height: 52,
      ),
    );
  }
}
