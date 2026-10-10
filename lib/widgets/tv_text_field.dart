import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'tv.dart';

/// A [TextField] that behaves on a TV. With a remote, landing on a text box must not pop the keyboard
/// up (it covers the screen and traps the D-pad), so in TV mode the box is just a focusable field that
/// shows what is typed. OK (or Enter) turns it into the real text input and opens the keyboard; Done,
/// Back, or moving away puts it back. Everywhere else it is a plain [TextField].
class TvTextField extends StatefulWidget {
  final TextEditingController? controller;
  final FocusNode? focusNode;
  final bool autofocus;
  final InputDecoration decoration;
  final TextStyle? style;
  final Color? cursorColor;
  final double cursorWidth;
  final Radius? cursorRadius;
  final TextInputAction? textInputAction;
  final TextInputType? keyboardType;
  final TextCapitalization textCapitalization;
  final bool obscureText;
  final int? maxLength, minLines;
  final int? maxLines;
  final ValueChanged<String>? onChanged, onSubmitted;

  const TvTextField({
    super.key,
    this.controller,
    this.focusNode,
    this.autofocus = false,
    this.decoration = const InputDecoration(),
    this.style,
    this.cursorColor,
    this.cursorWidth = 2,
    this.cursorRadius,
    this.textInputAction,
    this.keyboardType,
    this.textCapitalization = TextCapitalization.none,
    this.obscureText = false,
    this.maxLength,
    this.minLines,
    this.maxLines = 1,
    this.onChanged,
    this.onSubmitted,
  });

  @override
  State<TvTextField> createState() => _TvTextFieldState();
}

final _selectKeys = {
  LogicalKeyboardKey.select,
  LogicalKeyboardKey.enter,
  LogicalKeyboardKey.numpadEnter,
  LogicalKeyboardKey.gameButtonA,
};

class _TvTextFieldState extends State<TvTextField> {
  TextEditingController? _own;
  late final FocusNode _display = FocusNode(debugLabel: 'tv field');
  late final FocusNode _field = FocusNode(debugLabel: 'tv field input');
  bool _editing = false;

  TextEditingController get _c => widget.controller ?? (_own ??= TextEditingController());

  @override
  void initState() {
    super.initState();
    _field.addListener(_fieldFocus);
    _display.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _field.removeListener(_fieldFocus);
    _field.dispose();
    _display.dispose();
    _own?.dispose();
    super.dispose();
  }

  void _fieldFocus() {
    // Moving away with the D-pad ends editing without pulling focus back.
    if (!_field.hasFocus && _editing && mounted) setState(() => _editing = false);
  }

  void _start() {
    if (!_editing) setState(() => _editing = true);
  }

  void _stop() {
    if (!_editing) return;
    setState(() => _editing = false);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _display.requestFocus();
    });
  }

  @override
  Widget build(BuildContext context) {
    final w = widget;
    if (!TvScope.of(context)) {
      return TextField(
        controller: w.controller,
        focusNode: w.focusNode,
        autofocus: w.autofocus,
        decoration: w.decoration,
        style: w.style,
        cursorColor: w.cursorColor,
        cursorWidth: w.cursorWidth,
        cursorRadius: w.cursorRadius,
        textInputAction: w.textInputAction,
        keyboardType: w.keyboardType,
        textCapitalization: w.textCapitalization,
        obscureText: w.obscureText,
        maxLength: w.maxLength,
        minLines: w.minLines,
        maxLines: w.maxLines,
        onChanged: w.onChanged,
        onSubmitted: w.onSubmitted,
      );
    }
    if (_editing) {
      return Focus(
        canRequestFocus: false,
        onKeyEvent: (_, e) {
          if (e is KeyDownEvent &&
              (e.logicalKey == LogicalKeyboardKey.goBack || e.logicalKey == LogicalKeyboardKey.escape)) {
            _stop();
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        },
        child: TextField(
          controller: _c,
          focusNode: _field,
          autofocus: true,
          decoration: w.decoration,
          style: w.style,
          cursorColor: w.cursorColor,
          cursorWidth: w.cursorWidth,
          cursorRadius: w.cursorRadius,
          textInputAction: w.textInputAction,
          keyboardType: w.keyboardType,
          textCapitalization: w.textCapitalization,
          obscureText: w.obscureText,
          maxLength: w.maxLength,
          minLines: w.minLines,
          maxLines: w.maxLines,
          onChanged: w.onChanged,
          onSubmitted: (v) {
            w.onSubmitted?.call(v);
            _stop();
          },
        ),
      );
    }
    final theme = Theme.of(context);
    final style = w.style ?? theme.textTheme.bodyLarge;
    return Focus(
      focusNode: w.focusNode ?? _display,
      autofocus: w.autofocus,
      onKeyEvent: (_, e) {
        if (e is KeyDownEvent && _selectKeys.contains(e.logicalKey)) {
          _start();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _start,
        child: ListenableBuilder(
          listenable: _c,
          builder: (_, __) {
            final text = _c.text;
            final shown = w.obscureText ? '•' * text.length : text;
            return InputDecorator(
              decoration: w.decoration.copyWith(counterText: ''),
              isEmpty: text.isEmpty,
              isFocused: (w.focusNode ?? _display).hasFocus,
              baseStyle: style,
              child: Text(shown,
                  style: style,
                  maxLines: w.maxLines ?? 1,
                  overflow: TextOverflow.ellipsis),
            );
          },
        ),
      ),
    );
  }
}
