import 'package:shared_preferences/shared_preferences.dart';

class GaxConfig {
  final String token;
  final String repo;
  final String branch;
  const GaxConfig({this.token = '', this.repo = '', this.branch = ''});
}

/// Autosaves GitHub defaults (PAT, repo, branch) — set once from the
/// Settings screen, reused every time you push from Editor or File Manager.
class PrefsService {
  static const _kToken = 'gax_pat_token';
  static const _kRepo = 'gax_repo';
  static const _kBranch = 'gax_branch';

  Future<void> save(GaxConfig config) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kToken, config.token);
    await prefs.setString(_kRepo, config.repo);
    await prefs.setString(_kBranch, config.branch);
  }

  Future<GaxConfig> load() async {
    final prefs = await SharedPreferences.getInstance();
    return GaxConfig(
      token: prefs.getString(_kToken) ?? '',
      repo: prefs.getString(_kRepo) ?? '',
      branch: prefs.getString(_kBranch) ?? '',
    );
  }
}
