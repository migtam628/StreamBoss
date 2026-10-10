import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../widgets/tv.dart';
import 'ui_layout.dart';

/// A tappable, focusable surface whose look is up to [builder]. Gives the focus ring every
/// control needs on a TV: white and bold there, accent-colored elsewhere.
class FocusSurface extends StatefulWidget {
  final Widget Function(BuildContext context, bool focused) builder;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final ValueChanged<bool>? onFocus;
  final double radius;
  final bool autofocus;
  final String? semanticLabel;
  const FocusSurface({
    super.key,
    required this.builder,
    required this.onTap,
    this.onLongPress,
    this.onFocus,
    this.radius = 12,
    this.autofocus = false,
    this.semanticLabel,
  });

  @override
  State<FocusSurface> createState() => _FocusSurfaceState();
}

class _FocusSurfaceState extends State<FocusSurface> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final p = LayoutPalette.of(context);
    final tv = TvScope.of(context);
    Widget w = AnimatedContainer(
      duration: const Duration(milliseconds: 100),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(widget.radius),
        border: Border.all(
            color: _focused ? (tv ? p.ring : p.accent) : Colors.transparent,
            width: 3),
        boxShadow: tv && _focused
            ? [
                BoxShadow(
                    color: p.accent.withValues(alpha: 0.35), blurRadius: 18)
              ]
            : null,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(
            widget.radius - 2 < 0 ? 0 : widget.radius - 2),
        child: InkWell(
          autofocus: widget.autofocus,
          onFocusChange: (f) {
            setState(() => _focused = f);
            widget.onFocus?.call(f);
          },
          onTap: widget.onTap,
          onLongPress: widget.onLongPress,
          child: widget.builder(context, _focused),
        ),
      ),
    );
    // A remote has no long press: its Menu, Info and yellow keys do the same thing on whatever is focused.
    if (widget.onLongPress != null) {
      w = Focus(
        canRequestFocus: false,
        skipTraversal: true,
        onKeyEvent: (_, e) {
          final k = e.logicalKey;
          if (e is KeyDownEvent &&
              (k == LogicalKeyboardKey.contextMenu ||
                  k == LogicalKeyboardKey.info ||
                  k == LogicalKeyboardKey.colorF2Yellow)) {
            widget.onLongPress!();
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        },
        child: w,
      );
    }
    if (widget.semanticLabel != null) {
      w = Semantics(label: widget.semanticLabel, button: true, child: w);
    }
    return w;
  }
}

/// Small uppercase label above a group of content.
class Eyebrow extends StatelessWidget {
  final String text;
  final Color? color;
  const Eyebrow(this.text, {super.key, this.color});

  @override
  Widget build(BuildContext context) => Text(
        text.toUpperCase(),
        style: TextStyle(
            color: color ?? LayoutPalette.of(context).accent2,
            fontSize: 13,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.6),
      );
}

/// A horizontally scrolling row of choice chips, focusable on a TV.
class ChipRow extends StatelessWidget {
  final List<String> labels;
  final int selected;
  final ValueChanged<int> onSelect;
  final EdgeInsetsGeometry padding;
  const ChipRow(
      {super.key,
      required this.labels,
      required this.selected,
      required this.onSelect,
      this.padding = const EdgeInsets.symmetric(horizontal: 12, vertical: 8)});

  @override
  Widget build(BuildContext context) {
    final p = LayoutPalette.of(context);
    return SizedBox(
      height: 56,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: padding,
        itemCount: labels.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (_, i) => FocusSurface(
          radius: 22,
          semanticLabel: labels[i],
          onTap: () => onSelect(i),
          builder: (_, __) => Container(
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            color: i == selected ? p.accent : p.wash(),
            child: Text(labels[i],
                style: TextStyle(
                    color: i == selected ? p.onAccent : p.text,
                    fontWeight:
                        i == selected ? FontWeight.w700 : FontWeight.w500)),
          ),
        ),
      ),
    );
  }
}
