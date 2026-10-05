import 'package:flutter_test/flutter_test.dart';
import 'package:streamboss/services/shaders.dart';
import 'package:streamboss/state/settings_state.dart';

void main() {
  test('built-in shaders are well-formed mpv hooks with unique ids', () {
    expect(builtinShaders.map((e) => e.id).toSet().length, builtinShaders.length);
    for (final s in builtinShaders) {
      expect(s.source, contains('//!HOOK'), reason: s.id);
      expect(s.source, contains('//!BIND HOOKED'), reason: s.id);
      expect(s.source, contains('vec4 hook()'), reason: s.id);
    }
  });

  test('reconcileOrder keeps saved order, drops unknown, appends new', () {
    final order = reconcileOrder(['grain', 'gone', 'sharpen'], builtinShaders);
    expect(order.take(2), ['grain', 'sharpen']);
    expect(order.contains('gone'), isFalse);
    expect(order.toSet(), builtinShaders.map((e) => e.id).toSet());
  });

  test('active shaders follow order and enabled set; map round-trips', () {
    final a = SettingsState()
      ..setShaders(order: ['warm', 'sharpen'], enabled: {'sharpen', 'warm'});
    expect(a.activeShaders.map((e) => e.id), ['warm', 'sharpen']);
    final b = SettingsState()..applyShaderMap(a.toMap());
    expect(b.activeShaders.map((e) => e.id), ['warm', 'sharpen']);
  });
}
