import 'package:flutter/material.dart';
import '../theme.dart';

/// Tappable tile with a visible focus ring + scale, so D-pad / keyboard / remote
/// navigation works on TV, desktop and web.
class FocusCard extends StatefulWidget {
  final Widget child;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final double radius;
  final bool autofocus;

  const FocusCard({
    super.key,
    required this.child,
    required this.onTap,
    this.onLongPress,
    this.radius = 14,
    this.autofocus = false,
  });

  @override
  State<FocusCard> createState() => _FocusCardState();
}

class _FocusCardState extends State<FocusCard> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    return AnimatedScale(
      scale: _focused ? 1.06 : 1,
      duration: const Duration(milliseconds: 120),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(widget.radius + 3),
          border: Border.all(
              color: _focused ? Boss.accent : Colors.transparent, width: 3),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(widget.radius),
          child: InkWell(
            autofocus: widget.autofocus,
            onFocusChange: (f) => setState(() => _focused = f),
            onTap: widget.onTap,
            onLongPress: widget.onLongPress,
            child: widget.child,
          ),
        ),
      ),
    );
  }
}
