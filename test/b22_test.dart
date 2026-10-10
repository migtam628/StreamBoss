import 'package:flutter_test/flutter_test.dart';
import 'package:streamboss/services/nav_guard.dart';

void main() {
  group('NavGuard', () {
    setUp(NavGuard.reset);

    test('the first open goes through, a second right after does not', () {
      final t = DateTime(2026, 1, 1, 12);
      expect(NavGuard.allow(now: t), isTrue);
      expect(NavGuard.allow(now: t.add(const Duration(milliseconds: 200))), isFalse);
      expect(NavGuard.allow(now: t.add(const Duration(milliseconds: 600))), isFalse);
    });

    test('after the gap another open is fine', () {
      final t = DateTime(2026, 1, 1, 12);
      expect(NavGuard.allow(now: t), isTrue);
      expect(NavGuard.allow(now: t.add(const Duration(milliseconds: 800))), isTrue);
    });

    test('a refused open does not push the window back', () {
      final t = DateTime(2026, 1, 1, 12);
      NavGuard.allow(now: t);
      NavGuard.allow(now: t.add(const Duration(milliseconds: 500)));
      expect(NavGuard.allow(now: t.add(const Duration(milliseconds: 750))), isTrue);
    });
  });

  group('Zap', () {
    test('five quick presses make one move', () {
      final z = Zap();
      var to = 0;
      for (var i = 0; i < 5; i++) {
        to = z.step(10, 1, 100);
      }
      expect(to, 15);
      expect(z.take(), 15);
      expect(z.take(), isNull);
    });

    test('it wraps at both ends', () {
      expect(Zap().step(0, -1, 50), 49);
      expect(Zap().step(49, 1, 50), 0);
      final z = Zap()..aim(3);
      expect(z.step(40, -5, 50), 48);
    });

    test('up and down cancel out', () {
      final z = Zap();
      z.step(7, 1, 20);
      expect(z.step(7, -1, 20), 7);
    });

    test('a typed number sets the target', () {
      final z = Zap()..aim(33);
      expect(z.take(), 33);
    });
  });
}
