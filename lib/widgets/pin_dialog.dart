import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../layouts/common.dart';
import '../layouts/ui_layout.dart';
import '../state/profiles_state.dart';

/// Asks for the PIN and checks it. True when it was right (or no PIN is set).
Future<bool> askPin(BuildContext context, ProfilesState ps,
    {String title = 'Enter PIN', String? hint}) async {
  if (!ps.hasPin) return true;
  final r =
      await _pinDialog(context, title: title, hint: hint, validate: (pin) {
    return switch (ps.checkPin(pin)) {
      PinResult.ok => null,
      PinResult.wrong => 'Wrong PIN',
      PinResult.lockedOut =>
        'Too many tries. Wait ${ps.lockedSeconds} seconds.',
    };
  });
  return r != null;
}

/// Asks for a new PIN twice. Null when cancelled.
Future<String?> askNewPin(BuildContext context,
    {String title = 'Choose a PIN'}) async {
  final first = await _pinDialog(context,
      title: title,
      hint: 'Four digits. It guards Kids profiles and locked profiles.',
      validate: (_) => null);
  if (first == null || !context.mounted) return null;
  return _pinDialog(context,
      title: 'Enter it again',
      validate: (pin) => pin == first ? null : 'The two PINs do not match');
}

Future<String?> _pinDialog(BuildContext context,
        {required String title,
        String? hint,
        required String? Function(String pin) validate}) =>
    showDialog<String>(
      context: context,
      builder: (_) => _PinDialog(title: title, hint: hint, validate: validate),
    );

class _PinDialog extends StatefulWidget {
  final String title;
  final String? hint;
  final String? Function(String pin) validate;
  const _PinDialog({required this.title, this.hint, required this.validate});

  @override
  State<_PinDialog> createState() => _PinDialogState();
}

class _PinDialogState extends State<_PinDialog> {
  String _digits = '';
  String? _error;

  void _type(String d) {
    if (_digits.length >= 4) return;
    setState(() {
      _digits += d;
      _error = null;
    });
    if (_digits.length == 4) {
      final err = widget.validate(_digits);
      if (err == null) {
        Navigator.of(context).pop(_digits);
      } else {
        setState(() {
          _error = err;
          _digits = '';
        });
      }
    }
  }

  void _back() {
    if (_digits.isEmpty) return;
    setState(() => _digits = _digits.substring(0, _digits.length - 1));
  }

  KeyEventResult _key(FocusNode _, KeyEvent e) {
    if (e is! KeyDownEvent) return KeyEventResult.ignored;
    final ch = e.character;
    if (ch != null && RegExp(r'^\d$').hasMatch(ch)) {
      _type(ch);
      return KeyEventResult.handled;
    }
    if (e.logicalKey == LogicalKeyboardKey.backspace) {
      _back();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  Widget _key1(LayoutPalette p, String label, VoidCallback onTap,
          {bool autofocus = false, IconData? icon}) =>
      FocusSurface(
        radius: 30,
        autofocus: autofocus,
        semanticLabel: icon == null ? 'Digit $label' : label,
        onTap: onTap,
        builder: (_, __) => Container(
          height: 56,
          alignment: Alignment.center,
          color: p.wash(),
          child: icon != null
              ? Icon(icon, color: p.text)
              : Text(label,
                  style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w700,
                      color: p.text)),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final p = LayoutPalette.of(context);
    return Focus(
      onKeyEvent: _key,
      child: AlertDialog(
        title: Text(widget.title, textAlign: TextAlign.center),
        content: SizedBox(
          width: 280,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            if (widget.hint != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Text(widget.hint!,
                    textAlign: TextAlign.center,
                    style: TextStyle(color: p.muted, fontSize: 13)),
              ),
            Semantics(
              label: '${_digits.length} of 4 digits entered',
              child:
                  Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                for (var i = 0; i < 4; i++)
                  Container(
                    margin:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
                    width: 16,
                    height: 16,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: i < _digits.length ? p.accent : Colors.transparent,
                      border: Border.all(
                          color: i < _digits.length ? p.accent : p.muted,
                          width: 2),
                    ),
                  ),
              ]),
            ),
            SizedBox(
              height: 22,
              child: _error == null
                  ? null
                  : Text(_error!,
                      style: TextStyle(
                          color: p.accent2, fontWeight: FontWeight.w600)),
            ),
            const SizedBox(height: 6),
            GridView.count(
              shrinkWrap: true,
              crossAxisCount: 3,
              mainAxisSpacing: 8,
              crossAxisSpacing: 8,
              childAspectRatio: 1.45,
              physics: const NeverScrollableScrollPhysics(),
              children: [
                for (var d = 1; d <= 9; d++)
                  _key1(p, '$d', () => _type('$d'), autofocus: d == 1),
                _key1(p, 'Cancel', () => Navigator.of(context).pop(),
                    icon: Icons.close),
                _key1(p, '0', () => _type('0')),
                _key1(p, 'Delete', _back, icon: Icons.backspace_outlined),
              ],
            ),
          ]),
        ),
      ),
    );
  }
}
