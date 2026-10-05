import 'dart:convert';
import 'package:http/http.dart' as http;
import '../app_info.dart';

/// Compares dotted versions ("v1.2.3", "1.2.3-rc1" -> 1.2.3). Positive when [a] is newer than [b].
int compareVersions(String a, String b) {
  List<int> parts(String v) {
    final core = v.trim().replaceFirst(RegExp(r'^[vV]'), '').split(RegExp(r'[-+]')).first;
    return core.split('.').map((e) => int.tryParse(e) ?? 0).toList();
  }

  final x = parts(a), y = parts(b);
  for (var i = 0; i < (x.length > y.length ? x.length : y.length); i++) {
    final d = (i < x.length ? x[i] : 0) - (i < y.length ? y[i] : 0);
    if (d != 0) return d;
  }
  return 0;
}

class UpdateInfo {
  final String latest; // e.g. 0.2.0
  final String url;
  final bool newer;
  const UpdateInfo(this.latest, this.url, this.newer);
}

/// Asks GitHub for the latest published release and compares it with [current].
Future<UpdateInfo> checkForUpdate(String current, {http.Client? client}) async {
  final c = client ?? http.Client();
  final res = await c
      .get(Uri.parse('https://api.github.com/repos/$kRepoSlug/releases/latest'),
          headers: {'Accept': 'application/vnd.github+json'})
      .timeout(const Duration(seconds: 15));
  if (res.statusCode == 404) throw Exception('No releases have been published yet.');
  if (res.statusCode != 200) throw Exception('GitHub answered ${res.statusCode}.');
  final j = jsonDecode(res.body) as Map<String, dynamic>;
  final tag = (j['tag_name'] as String? ?? '').replaceFirst(RegExp(r'^[vV]'), '');
  return UpdateInfo(tag, (j['html_url'] as String?) ?? kReleasesUrl, compareVersions(tag, current) > 0);
}
