import 'package:shared_preferences/shared_preferences.dart';

class GaxConfig {
  final String token;
  final String repo;
  final String branch;
  final String path;
  const GaxConfig({this.token = '', this.repo = '', this.branch = '', this.path = ''});
}

/// Autosaves GitHub config (PAT, repo, branch, path) so Arnab never
/// re-types them on every app launch.
class PrefsService {
  static const _kToken = 'gax_pat_token';
  static const _kRepo = 'gax_repo';
  static const _kBranch = 'gax_branch';
  static const _kPath = 'gax_path';

  Future<void> save(GaxConfig config) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kToken, config.token);
    await prefs.setString(_kRepo, config.repo);
    await prefs.setString(_kBranch, config.branch);
    await prefs.setString(_kPath, config.path);
  }

  Future<GaxConfig> load() async {
    final prefs = await SharedPreferences.getInstance();
    return GaxConfig(
      token: prefs.getString(_kToken) ?? '',
      repo: prefs.getString(_kRepo) ?? '',
      branch: prefs.getString(_kBranch) ?? '',
      path: prefs.getString(_kPath) ?? '',
    );
  }
}
