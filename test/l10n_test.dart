import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:streamboss/l10n/l10n.dart';
import 'package:streamboss/l10n/strings_es.dart';
import 'package:streamboss/l10n/strings_it.dart';
import 'package:streamboss/l10n/strings_pt.dart';
import 'package:streamboss/screens/settings/settings_pages.dart';
import 'package:streamboss/state/app_state.dart';
import 'package:streamboss/state/settings_state.dart';
import 'package:streamboss/theme.dart';

/// Every text the code passes to tr() or trf() as a plain string (adjacent literals joined).
Set<String> keysInCode() {
  final out = <String>{};
  final call = RegExp(
      r"""(?<![\w.])trf?\(\s*((?:(?:'(?:[^'\\\n]|\\.)*'|"(?:[^"\\\n]|\\.)*")\s*)+)""");
  final lit =
      RegExp(r"""'((?:[^'\\\n]|\\.)*)'|"((?:[^"\\\n]|\\.)*)" """.trim());
  for (final f
      in Directory('lib').listSync(recursive: true).whereType<File>()) {
    if (!f.path.endsWith('.dart') ||
        f.path
            .contains('${Platform.pathSeparator}l10n${Platform.pathSeparator}')) {
      continue;
    }
    for (final m in call.allMatches(f.readAsStringSync())) {
      final parts = [for (final l in lit.allMatches(m[1]!)) l[1] ?? l[2]!];
      if (parts.any((p) => RegExp(r'(?<!\\)\$').hasMatch(p))) {
        continue; // has a value in it: not a plain text
      }
      final text = parts
          .map((p) => p.replaceAllMapped(RegExp(r'\\(.)'),
              (e) => switch (e[1]) { 'n' => '\n', 't' => '\t', var c => c! }))
          .join();
      if (!text.startsWith('//')) out.add(text);
    }
  }
  return out;
}

void main() {
  final tables = {'es': stringsEs, 'it': stringsIt, 'pt': stringsPt};

  tearDown(() => L10n.code = 'en');

  test('every text in the code has a translation in every language', () {
    final keys = keysInCode();
    expect(keys.length, greaterThan(400)); // the scan itself works
    for (final e in tables.entries) {
      final missing = keys.where((k) => !e.value.containsKey(k)).toList()
        ..sort();
      expect(missing, isEmpty,
          reason:
              '${e.key} lacks ${missing.length}: ${missing.take(5).join(' | ')} (python3 tool/l10n_keys.py missing ${e.key})');
    }
  });

  test(
      'the three languages have the same texts, none empty, and the same {values} in each',
      () {
    final base = stringsEs.keys.toSet();
    for (final e in tables.entries) {
      expect(e.value.keys.toSet(), base, reason: e.key);
      for (final kv in e.value.entries) {
        expect(kv.value.trim(), isNotEmpty, reason: '${e.key}: ${kv.key}');
        final want = RegExp(r'\{\w+\}')
            .allMatches(kv.key)
            .map((m) => m[0])
            .toList()
          ..sort();
        final got = RegExp(r'\{\w+\}')
            .allMatches(kv.value)
            .map((m) => m[0])
            .toList()
          ..sort();
        expect(got, want, reason: '${e.key}: ${kv.key}');
      }
    }
  });

  test('tr falls back to English for anything unknown, and trf fills in values',
      () {
    expect(tr('Settings'), 'Settings');
    L10n.code = 'es';
    expect(tr('Settings'), 'Ajustes');
    expect(tr('A text no table knows'), 'A text no table knows');
    expect(trf('Step {n} of {total}', {'n': 2, 'total': 5}), 'Paso 2 de 5');
    L10n.code = 'it';
    expect(tr('Movies'), 'Film');
    L10n.code = 'pt';
    expect(tr('Movies'), 'Filmes');
    expect(trf('{n} results', {'n': 3}), '3 resultados');
  });

  test(
      'the setting picks the language: a code, or the device language when it is one we have',
      () {
    expect(AppLanguage.resolve('es'), 'es');
    expect(AppLanguage.resolve('system', device: 'it'), 'it');
    expect(AppLanguage.resolve('system', device: 'ja'), 'en');
    expect(AppLanguage.resolve('xx'), 'en');
    expect(L10n.use('pt'), isTrue);
    expect(L10n.code, 'pt');
    expect(L10n.use('pt'), isFalse); // unchanged
    expect(AppLanguage.nameOf('it'), 'Italiano');
  });

  testWidgets('changing the language rebuilds text that is already on screen',
      (t) async {
    SharedPreferences.setMockInitialValues({});
    final st = SettingsState();
    await st.init();
    await t.pumpWidget(ChangeNotifierProvider.value(
      value: st,
      child: MaterialApp(
          home: Scaffold(body: Builder(builder: (c) => Text(tr('Search'))))),
    ));
    expect(find.text('Search'), findsOneWidget);
    expect(L10n.use('es'), isTrue);
    rebuildEverything();
    await t.pump();
    expect(find.text('Buscar'), findsOneWidget);
    expect(st.language, 'system');
    st.set('language', 'it');
    expect(st.language, 'it');
  });

  testWidgets('a settings page reads in the chosen language', (t) async {
    SharedPreferences.setMockInitialValues({'language': 'pt'});
    final st = SettingsState();
    await st.init();
    expect(st.language, 'pt');
    L10n.use(st.language);
    final app = AppState()..bindSettings(st);
    t.view.physicalSize = const Size(1200, 4000);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider<AppState>.value(value: app),
        ChangeNotifierProvider<SettingsState>.value(value: st),
      ],
      child: MaterialApp(
          theme: Boss.theme(),
          home: Scaffold(
              body: Builder(builder: (c) => settingsSections[3].builder(c)))),
    ));
    await t.pumpAndSettle();
    expect(find.text('Idioma do app'), findsOneWidget);
    expect(find.text('IDIOMA'), findsOneWidget);
    expect(find.text('LANGUAGE'), findsNothing);
    // The picker shows the chosen language by its own name.
    expect(find.text('Português'), findsOneWidget);
  });

  test(
      'pseudo mode marks every translated text, so a screen can be checked for texts that bypass tr()',
      () {
    L10n.pseudo = true;
    addTearDown(() => L10n.pseudo = false);
    expect(tr('Play'), '⟦Play⟧');
  });
}
