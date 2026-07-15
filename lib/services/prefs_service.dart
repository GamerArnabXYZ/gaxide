import 'package:shared_preferences/shared_preferences.dart';

class GaxConfig {
  final String token;
  const GaxConfig({this.token = ''});
}

/// Only the GitHub PAT is a global setting now — repo & branch are
/// auto-detected per-project from each folder's own `.git` metadata.
class PrefsService {
  static const _kToken = 'gax_pat_token';

  Future<void> save(GaxConfig config) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kToken, config.token);
  }

  Future<GaxConfig> load() async {
    final prefs = await SharedPreferences.getInstance();
    return GaxConfig(token: prefs.getString(_kToken) ?? '');
  }
}
