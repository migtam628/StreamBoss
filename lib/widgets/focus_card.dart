import 'package:flutter/material.dart';
import '../layouts/ui_layout.dart';
import 'tv.dart';

/// Tappable tile with a visible focus ring + scale, so D-pad / keyboard / remote
/// navigation works on TV, desktop and web.
class FocusCard extends StatefulWidget {
  final Widget child;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final double radius;
  final bool autofocus;
  final ValueChanged<bool>? onFocus;

  const FocusCard({
    super.key,
    required this.child,
    required this.onTap,
    this.onLongPress,
    this.radius = 14,
    this.autofocus = false,
    this.onFocus,
  });

  @override
  State<FocusCard> createState() => _FocusCardState();
}

class _FocusCardState extends State<FocusCard> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    // On a TV the focused card is the cursor: bigger lift, a white ring and a glow.
    final tv = TvScope.of(context);
    final pal = LayoutPalette.of(context);
    return AnimatedScale(
      scale: _focused ? (tv ? 1.12 : 1.06) : 1,
      duration: const Duration(milliseconds: 120),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(widget.radius + 3),
          border: Border.all(
              color: _focused ? (tv ? pal.ring : pal.accent) : Colors.transparent, width: tv ? 4 : 3),
          boxShadow: tv && _focused
              ? [BoxShadow(color: pal.accent.withValues(alpha: 0.55), blurRadius: 24, spreadRadius: 2)]
              : null,
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(widget.radius),
          child: InkWell(
            autofocus: widget.autofocus,
            onFocusChange: (f) {
              setState(() => _focused = f);
              widget.onFocus?.call(f);
            },
            onTap: widget.onTap,
            onLongPress: widget.onLongPress,
            child: widget.child,
          ),
        ),
      ),
    );
  }
}
