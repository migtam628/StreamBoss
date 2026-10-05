import 'dart:convert';
import 'package:http/http.dart' as http;
import '../app_info.dart';

/// A parsed version such as `0.2.3`, `0.3.0b2`, `0.3.0-rc1` or `0.3.0-beta.2`.
class AppVersion implements Comparable<AppVersion> {
  final List<int> core;
  final int? preRank; // null = a normal release; alpha 0 < beta 1 < rc 2
  final int preNum;
  const AppVersion(this.core, this.preRank, this.preNum);

  factory AppVersion.parse(String raw) {
    final v = raw.trim().replaceFirst(RegExp(r'^[vV]'), '').split('+').first;
    final m = RegExp(r'^(\d+(?:\.\d+)*)(?:-?([A-Za-z]+)\.?(\d*))?').firstMatch(v);
    if (m == null) return const AppVersion([0], null, 0);
    final core = m[1]!.split('.').map(int.parse).toList();
    final kind = m[2]?.toLowerCase();
    if (kind == null) return AppVersion(core, null, 0);
    final rank = switch (kind) { 'a' || 'alpha' => 0, 'rc' => 2, _ => 1 }; // b, beta and anything else
    return AppVersion(core, rank, int.tryParse(m[3] ?? '') ?? 0);
  }

  bool get isPrerelease => preRank != null;

  @override
  int compareTo(AppVersion o) {
    for (var i = 0; i < (core.length > o.core.length ? core.length : o.core.length); i++) {
      final d = (i < core.length ? core[i] : 0) - (i < o.core.length ? o.core[i] : 0);
      if (d != 0) return d;
    }
    // Same x.y.z: the real release is newer than any of its betas / release candidates.
    if (preRank == null && o.preRank == null) return 0;
    if (preRank == null) return 1;
    if (o.preRank == null) return -1;
    return preRank! != o.preRank! ? preRank! - o.preRank! : preNum - o.preNum;
  }
}

/// Positive when [a] is newer than [b]. Betas order before their release:
/// 0.3.0b1 < 0.3.0b2 < 0.3.0-rc1 < 0.3.0 < 0.3.1b1.
int compareVersions(String a, String b) => AppVersion.parse(a).compareTo(AppVersion.parse(b));

bool isPrerelease(String v) => AppVersion.parse(v).isPrerelease;

class UpdateInfo {
  final String latest; // e.g. 0.2.0 or 0.3.0b2
  final String url;
  final bool newer;
  const UpdateInfo(this.latest, this.url, this.newer);
}

/// Asks GitHub for a newer release than [current]. Stable builds only look at stable releases;
/// a beta build also sees newer betas, so beta testers keep getting beta updates.
Future<UpdateInfo> checkForUpdate(String current, {http.Client? client}) async {
  final c = client ?? http.Client();
  final beta = isPrerelease(current);
  final uri = Uri.parse('https://api.github.com/repos/$kRepoSlug/releases${beta ? '?per_page=30' : '/latest'}');
  final res = await c.get(uri, headers: {'Accept': 'application/vnd.github+json'}).timeout(const Duration(seconds: 15));
  if (res.statusCode == 404) throw Exception('No releases have been published yet.');
  if (res.statusCode != 200) throw Exception('GitHub answered ${res.statusCode}.');

  final body = jsonDecode(res.body);
  final releases = (body is List ? body : [body]).whereType<Map<String, dynamic>>().where((j) => j['draft'] != true).toList();
  if (releases.isEmpty) throw Exception('No releases have been published yet.');

  String tagOf(Map<String, dynamic> j) => (j['tag_name'] as String? ?? '').replaceFirst(RegExp(r'^[vV]'), '');
  releases.sort((a, b) => compareVersions(tagOf(b), tagOf(a)));
  final best = releases.first;
  final tag = tagOf(best);
  return UpdateInfo(tag, (best['html_url'] as String?) ?? kReleasesUrl, compareVersions(tag, current) > 0);
}
