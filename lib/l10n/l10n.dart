import 'dart:ui' show PlatformDispatcher;
import 'package:flutter/widgets.dart';
import 'strings_es.dart';
import 'strings_it.dart';
import 'strings_pt.dart';

/// The languages the app itself can show. Provider content (channel names, titles, guides) is never translated.
class AppLanguage {
  final String code, name;
  const AppLanguage(this.code, this.name);

  /// Each language is named in itself, so it can be found whatever language is on screen now.
  static const all = [
    AppLanguage('en', 'English'),
    AppLanguage('es', 'Español'),
    AppLanguage('it', 'Italiano'),
    AppLanguage('pt', 'Português'),
  ];

  static const system = 'system';

  /// The language to show for the setting [pref] ('system' follows the device, else a code).
  static String resolve(String pref, {String? device}) {
    final want = pref == system
        ? (device ?? PlatformDispatcher.instance.locale.languageCode)
        : pref;
    return all.any((l) => l.code == want) ? want : 'en';
  }

  static String nameOf(String pref) => pref == system
      ? 'Device language'
      : all.firstWhere((l) => l.code == pref, orElse: () => all.first).name;
}

const _tables = <String, Map<String, String>>{
  'es': stringsEs,
  'it': stringsIt,
  'pt': stringsPt
};

/// The language on screen. Set by [L10n.use] when the setting changes.
class L10n {
  static String code = 'en';

  /// Tests only: wraps every translated text in ⟦ ⟧.
  @visibleForTesting
  static bool pseudo = false;

  /// Switches the language; true when it changed (the app then rebuilds every screen).
  static bool use(String pref) {
    final next = AppLanguage.resolve(pref);
    if (next == code) return false;
    code = next;
    return true;
  }

  static Locale get locale => Locale(code);
}

/// The text for [en] in the language on screen: [en] itself in English and for anything not translated yet.
/// The English text is the key, so a missing translation can never show a blank or a code.
String tr(String en) {
  if (L10n.pseudo) {
    return '⟦$en⟧'; // tests: shows which text is not going through tr()
  }
  return L10n.code == 'en' ? en : (_tables[L10n.code]?[en] ?? en);
}

/// Like [tr] for text with numbers or names in it: write `{name}` where each value goes.
/// `trf('{n} episodes', {'n': 3})`.
String trf(String en, Map<String, Object?> values) {
  var out = tr(en);
  values.forEach((k, v) => out = out.replaceAll('{$k}', '$v'));
  return out;
}

/// Marks every widget as needing a rebuild, so text that was already on screen picks up a new language.
void rebuildEverything() {
  void visit(Element e) {
    e.markNeedsBuild();
    e.visitChildren(visit);
  }

  WidgetsBinding.instance.rootElement?.visitChildren(visit);
}
