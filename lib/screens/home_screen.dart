import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../layouts/home_views.dart';
import '../layouts/ui_layout.dart';
import '../state/settings_state.dart';

/// The Home tab. What it looks like depends on Settings > Appearance > Layout.
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) => LayoutHome(
      layout: context.select<SettingsState, UiLayout>((s) => s.layout));
}
