import 'package:flutter/material.dart';
import '../../layouts/ui_layout.dart';

/// Small building blocks shared by every settings page. All rows are plain ListTiles, so they
/// take focus from a D-pad / keyboard and show the theme's focus highlight.

class SettingsHeader extends StatelessWidget {
  final String text;
  const SettingsHeader(this.text, {super.key});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 22, 16, 4),
        child: Text(text.toUpperCase(),
            style: TextStyle(
                color: LayoutPalette.of(context).accent, fontWeight: FontWeight.w700, letterSpacing: 1.5, fontSize: 12)),
      );
}

class SwitchRow extends StatelessWidget {
  final IconData? icon;
  final String title;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;
  const SwitchRow({
    super.key,
    this.icon,
    required this.title,
    this.subtitle,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) => SwitchListTile(
        secondary: icon == null ? null : Icon(icon),
        title: Text(title),
        subtitle: subtitle == null ? null : Text(subtitle!),
        value: value,
        activeThumbColor: LayoutPalette.of(context).accent,
        onChanged: onChanged,
      );
}

/// A row that shows the current choice and opens a list to pick another.
class ChoiceRow<T> extends StatelessWidget {
  final IconData? icon;
  final String title;
  final String? subtitle;
  final T value;
  final List<(T, String)> options;
  final ValueChanged<T> onChanged;
  final bool enabled;
  const ChoiceRow({
    super.key,
    this.icon,
    required this.title,
    this.subtitle,
    required this.value,
    required this.options,
    required this.onChanged,
    this.enabled = true,
  });

  String get _label {
    for (final o in options) {
      if (o.$1 == value) return o.$2;
    }
    return 'Custom';
  }

  Future<void> _pick(BuildContext context) async {
    final picked = await showDialog<T>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: Text(title),
        children: [
          for (final o in options)
            ListTile(
              autofocus: o.$1 == value,
              title: Text(o.$2),
              trailing: o.$1 == value ? Icon(Icons.check, color: LayoutPalette.of(context).accent) : null,
              onTap: () => Navigator.pop(ctx, o.$1),
            ),
        ],
      ),
    );
    if (picked != null && picked != value) onChanged(picked);
  }

  @override
  Widget build(BuildContext context) => ListTile(
        enabled: enabled,
        leading: icon == null ? null : Icon(icon),
        title: Text(title),
        subtitle: subtitle == null ? null : Text(subtitle!),
        trailing: Row(mainAxisSize: MainAxisSize.min, children: [
          Text(_label, style: TextStyle(color: LayoutPalette.of(context).muted)),
          const SizedBox(width: 4),
          Icon(Icons.chevron_right, color: LayoutPalette.of(context).muted),
        ]),
        onTap: enabled ? () => _pick(context) : null,
      );
}

class SliderRow extends StatelessWidget {
  final IconData? icon;
  final String title;
  final double value;
  final double min, max;
  final int? divisions;
  final String Function(double) label;
  final ValueChanged<double> onChanged;
  const SliderRow({
    super.key,
    this.icon,
    required this.title,
    required this.value,
    required this.min,
    required this.max,
    this.divisions,
    required this.label,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) => ListTile(
        leading: icon == null ? null : Icon(icon),
        title: Text('$title: ${label(value)}'),
        subtitle: Slider(
          value: value.clamp(min, max),
          min: min,
          max: max,
          divisions: divisions,
          activeColor: LayoutPalette.of(context).accent,
          onChanged: onChanged,
        ),
      );
}

class ActionRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback? onTap;
  final bool destructive;
  const ActionRow({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.onTap,
    this.destructive = false,
  });

  @override
  Widget build(BuildContext context) {
    final color = destructive ? LayoutPalette.of(context).accent : null;
    return ListTile(
      enabled: onTap != null,
      leading: Icon(icon, color: color),
      title: Text(title, style: TextStyle(color: color)),
      subtitle: subtitle == null ? null : Text(subtitle!),
      onTap: onTap,
    );
  }
}

class InfoRow extends StatelessWidget {
  final String title;
  final String value;
  const InfoRow(this.title, this.value, {super.key});

  @override
  Widget build(BuildContext context) => ListTile(
        title: Text(title),
        trailing: Text(value, style: TextStyle(color: LayoutPalette.of(context).muted)),
      );
}

Future<bool> confirmDialog(
  BuildContext context, {
  required String title,
  required String body,
  String confirm = 'Confirm',
}) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: Text(body),
      actions: [
        TextButton(autofocus: true, onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(confirm)),
      ],
    ),
  );
  return ok == true;
}

void toast(BuildContext context, String message) =>
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
