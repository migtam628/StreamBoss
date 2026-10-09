import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../layouts/common.dart';
import '../layouts/ui_layout.dart';
import '../models/profile.dart';
import '../state/profiles_state.dart';
import '../widgets/pin_dialog.dart';
import '../widgets/tv.dart';

const _avatarColors = [
  Color(0xFFFF3D71),
  Color(0xFFFFB02E),
  Color(0xFF2FBF8F),
  Color(0xFF5B8CFF),
  Color(0xFF9D4EDD),
  Color(0xFFFF7B00),
];

Color avatarColor(Profile p) => _avatarColors[
    p.id.codeUnits.fold(0, (a, b) => a + b) % _avatarColors.length];

/// Round colored initial for a profile.
class ProfileAvatar extends StatelessWidget {
  final Profile profile;
  final double size;
  const ProfileAvatar(this.profile, {super.key, this.size = 96});

  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration:
            BoxDecoration(shape: BoxShape.circle, color: avatarColor(profile)),
        child: Text(
          profile.name.trim().isEmpty
              ? '?'
              : profile.name.trim().characters.first.toUpperCase(),
          style: TextStyle(
              fontSize: size * 0.46,
              fontWeight: FontWeight.w800,
              color: Colors.black.withValues(alpha: 0.78)),
        ),
      );
}

/// Moves to [target] after asking for the PIN when that is needed. True when it switched.
Future<bool> switchProfile(
    BuildContext context, ProfilesState ps, Profile target) async {
  if (target.id == ps.currentId) {
    ps.select(target.id);
    return true;
  }
  if (ps.needsPinToEnter(target)) {
    final ok = await askPin(context, ps,
        title: 'Enter PIN',
        hint: target.locked
            ? '${target.name} is locked.'
            : 'Leaving a Kids profile needs the PIN.');
    if (!ok) return false;
  }
  ps.select(target.id);
  return true;
}

/// "Who's watching?" Shown when the app starts with more than one profile, and from Settings.
class ProfilePickerScreen extends StatelessWidget {
  const ProfilePickerScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final ps = context.watch<ProfilesState>();
    final p = LayoutPalette.of(context);
    final tv = TvScope.of(context);
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Text("Who's watching?",
                  style: TextStyle(
                      fontSize: tv ? 44 : 30,
                      fontWeight: FontWeight.w800,
                      color: p.text)),
              const SizedBox(height: 32),
              Wrap(
                  spacing: 28,
                  runSpacing: 28,
                  alignment: WrapAlignment.center,
                  children: [
                    for (final pr in ps.profiles)
                      FocusSurface(
                        radius: 18,
                        autofocus: pr.id == ps.currentId,
                        semanticLabel: pr.name,
                        onTap: () async {
                          final nav = Navigator.of(context);
                          final done = await switchProfile(context, ps, pr);
                          if (done && nav.canPop()) nav.pop();
                        },
                        builder: (_, __) => Padding(
                          padding: const EdgeInsets.all(14),
                          child: SizedBox(
                            width: tv ? 150 : 110,
                            child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Stack(clipBehavior: Clip.none, children: [
                                    ProfileAvatar(pr, size: tv ? 120 : 88),
                                    if (pr.locked && ps.hasPin)
                                      Positioned(
                                        right: -2,
                                        bottom: -2,
                                        child: CircleAvatar(
                                            radius: 14,
                                            backgroundColor: p.bg,
                                            child: Icon(Icons.lock,
                                                size: 16, color: p.text)),
                                      ),
                                  ]),
                                  const SizedBox(height: 12),
                                  Text(pr.name,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                          fontSize: tv ? 22 : 17,
                                          fontWeight: FontWeight.w700,
                                          color: p.text)),
                                  if (pr.kids)
                                    Text('Kids',
                                        style: TextStyle(
                                            color: p.accent2,
                                            fontWeight: FontWeight.w600)),
                                ]),
                          ),
                        ),
                      ),
                  ]),
            ]),
          ),
        ),
      ),
    );
  }
}
