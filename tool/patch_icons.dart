// Run after `flutter create .`:  dart run tool/patch_icons.dart
// Puts the StreamBoss icon into the generated iOS, macOS, Windows and web projects in place of the Flutter
// default. (Android has its own, richer set: see tool/patch_android.dart. The drawings and the script that
// makes every size are in design/; the output is committed under tool/icons.)
import 'dart:convert';
import 'dart:io';

void main() {
  var n = 0;
  n += _appIconSet('ios/Runner/Assets.xcassets/AppIcon.appiconset', 'tool/icons/ios');
  n += _appIconSet('macos/Runner/Assets.xcassets/AppIcon.appiconset', 'tool/icons/mac');
  n += _copy('tool/icons/windows/app_icon.ico', 'windows/runner/resources/app_icon.ico');
  if (Directory('web').existsSync()) {
    for (final name in ['Icon-192.png', 'Icon-512.png', 'Icon-maskable-192.png', 'Icon-maskable-512.png']) {
      n += _copy('tool/icons/web/$name', 'web/icons/$name');
    }
    n += _copy('tool/icons/web/favicon.png', 'web/favicon.png');
  }
  stdout.writeln('Branded icon files written: $n.');
}

int _copy(String from, String to) {
  final dst = File(to);
  if (!dst.parent.existsSync()) return 0; // that platform was not generated
  File(from).copySync(to);
  return 1;
}

/// An Xcode icon set: Contents.json lists the files and the point size and scale of each; the pixel
/// size is the product, and the matching PNG is taken from [src].
int _appIconSet(String dir, String src) {
  final contents = File('$dir/Contents.json');
  if (!contents.existsSync()) return 0;
  final json = jsonDecode(contents.readAsStringSync()) as Map<String, dynamic>;
  var n = 0;
  for (final img in (json['images'] as List).cast<Map<String, dynamic>>()) {
    final file = img['filename'] as String?;
    final size = double.tryParse((img['size'] as String).split('x').first);
    final scale = double.tryParse((img['scale'] as String).replaceAll('x', ''));
    if (file == null || size == null || scale == null) continue;
    final px = (size * scale).round();
    final from = File('$src/$px.png');
    if (!from.existsSync()) {
      stderr.writeln('No $px px icon in $src for $file.');
      continue;
    }
    from.copySync('$dir/$file');
    n++;
  }
  return n;
}
