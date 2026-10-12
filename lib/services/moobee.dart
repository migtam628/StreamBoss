import 'package:flutter/foundation.dart' show TargetPlatform;
import '../app_info.dart';

/// Where MooBee is. An empty setting means the project's own (see [kMoobeeUrl]); a typed address must be https
/// (http only for this machine), else it is ignored. Null when there is nothing usable.
Uri? moobeeAddress(String setting) {
  final raw = setting.trim().isEmpty ? kMoobeeUrl : setting.trim();
  final u = Uri.tryParse(raw.contains('://') ? raw : 'https://$raw');
  if (u == null || u.host.isEmpty) return null;
  final local = u.host == 'localhost' || u.host == '127.0.0.1';
  if (u.scheme == 'https' || (u.scheme == 'http' && local)) return u;
  return null;
}

/// Whether the MooBee tab is in the menus: on by default, not on a TV (a remote cannot drive a web page), and only
/// with a usable address.
bool moobeeTabVisible(
        {required bool enabled, required bool isTv, required String address}) =>
    enabled && !isTv && moobeeAddress(address) != null;

/// Whether this platform can show a web page inside the app. Android, iOS and macOS can; Windows, Linux and the web
/// app open the page in the browser instead.
bool moobeeInApp({required bool web, required TargetPlatform platform}) =>
    !web &&
    (platform == TargetPlatform.android ||
        platform == TargetPlatform.iOS ||
        platform == TargetPlatform.macOS);

/// Whether a page the in-app view is about to open belongs to MooBee's own address. Anything else (a link out to
/// TMDB or YouTube, say) opens in the browser.
bool moobeeOwnPage(Uri home, Uri page) {
  if (page.scheme == 'about' || page.scheme == 'data' || page.scheme == 'blob') {
    return true;
  }
  return page.host == home.host && page.port == home.port;
}
