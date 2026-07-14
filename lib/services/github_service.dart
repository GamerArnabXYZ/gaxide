import 'dart:convert';
import 'package:http/http.dart' as http;

class GithubPushResult {
  final bool success;
  final String message;
  const GithubPushResult(this.success, this.message);
}

/// Handles all GitHub REST (Contents API) interactions.
class GithubService {
  Future<GithubPushResult> pushFile({
    required String token,
    required String repo,
    required String filePath,
    required String content,
    String branch = '',
    String commitMessage = 'Update via GAX IDE Mobile',
  }) async {
    final baseUrl = Uri.parse('https://api.github.com/repos/$repo/contents/$filePath');
    final headers = {
      'Authorization': 'token $token',
      'Accept': 'application/vnd.github.v3+json',
      'Content-Type': 'application/json',
    };

    try {
      // Step 1: check if file already exists (need its sha to update, not create).
      String? sha;
      final getUrl = branch.isEmpty ? baseUrl : baseUrl.replace(queryParameters: {'ref': branch});
      final getResponse = await http.get(getUrl, headers: headers);

      if (getResponse.statusCode == 200) {
        final decoded = jsonDecode(getResponse.body) as Map<String, dynamic>;
        sha = decoded['sha'] as String?;
      }

      // Step 2: build request payload.
      final body = <String, dynamic>{
        'message': commitMessage,
        'content': base64.encode(utf8.encode(content)),
        if (sha != null) 'sha': sha,
        if (branch.isNotEmpty) 'branch': branch,
      };

      final putResponse = await http.put(baseUrl, headers: headers, body: jsonEncode(body));

      if (putResponse.statusCode == 200 || putResponse.statusCode == 201) {
        return const GithubPushResult(true, '🚀 SUCCESS! Script pushed to GitHub.');
      }
      return GithubPushResult(
        false,
        '❌ FAILED [${putResponse.statusCode}]: ${putResponse.body}',
      );
    } catch (e) {
      return GithubPushResult(false, '❌ Network Exception: $e');
    }
  }
}
