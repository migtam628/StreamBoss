import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// A [Slider] a remote can get out of. Flutter's Slider uses all four arrow keys (Up and Down change
/// the value too), so once focus reached it a D-pad could not leave until Back was pressed. Here Left
/// and Right still change the value, and Up and Down move focus to whatever is above or below.
class TvSlider extends StatefulWidget {
  final double value, min, max;
  final int? divisions;
  final String? label;
  final Color? activeColor;
  final ValueChanged<double>? onChanged;
  const TvSlider({
    super.key,
    required this.value,
    required this.onChanged,
    this.min = 0,
    this.max = 1,
    this.divisions,
    this.label,
    this.activeColor,
  });

  @override
  State<TvSlider> createState() => _TvSliderState();
}

class _TvSliderState extends State<TvSlider> {
  late final FocusNode _node = FocusNode(debugLabel: 'slider', onKeyEvent: _key);

  KeyEventResult _key(FocusNode node, KeyEvent e) {
    if (e is KeyUpEvent) return KeyEventResult.ignored;
    final up = e.logicalKey == LogicalKeyboardKey.arrowUp;
    final down = e.logicalKey == LogicalKeyboardKey.arrowDown;
    if (!up && !down) return KeyEventResult.ignored;
    if (e is KeyDownEvent) node.focusInDirection(up ? TraversalDirection.up : TraversalDirection.down);
    return KeyEventResult.handled;
  }

  @override
  void dispose() {
    _node.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Slider(
        focusNode: _node,
        value: widget.value,
        min: widget.min,
        max: widget.max,
        divisions: widget.divisions,
        label: widget.label,
        activeColor: widget.activeColor,
        onChanged: widget.onChanged,
      );
}
