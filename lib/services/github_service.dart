import 'dart:convert';
import 'package:http/http.dart' as http;

class GithubPushResult {
  final bool success;
  final String message;
  const GithubPushResult(this.success, this.message);
}

/// Pushes an entire git-repo folder to GitHub as ONE atomic commit, using
/// the Git Data API (blobs -> tree -> commit -> branch ref update) instead
/// of one REST call per file. This is why push is a folder-level action —
/// a single commit properly represents "this project's current state".
class GithubService {
  Future<GithubPushResult> pushFolder({
    required String token,
    required String owner,
    required String repo,
    required String branch,
    required List<MapEntry<String, List<int>>> files,
    required String commitMessage,
    String authorName = 'GAX IDE',
  }) async {
    final headers = {
      'Authorization': 'token $token',
      'Accept': 'application/vnd.github.v3+json',
      'Content-Type': 'application/json',
    };
    final base = 'https://api.github.com/repos/$owner/$repo';

    if (files.isEmpty) {
      return const GithubPushResult(false, '❌ Nothing to push — folder is empty (or fully ignored).');
    }

    try {
      // 1. Latest commit SHA on the target branch.
      final refRes = await http.get(Uri.parse('$base/git/refs/heads/$branch'), headers: headers);
      if (refRes.statusCode != 200) {
        return GithubPushResult(false, '❌ Branch "$branch" not found on $owner/$repo [${refRes.statusCode}]');
      }
      final latestCommitSha = jsonDecode(refRes.body)['object']['sha'] as String;

      // 2. Base tree SHA of that commit.
      final commitRes = await http.get(Uri.parse('$base/git/commits/$latestCommitSha'), headers: headers);
      if (commitRes.statusCode != 200) {
        return GithubPushResult(false, '❌ Could not read base commit [${commitRes.statusCode}]');
      }
      final baseTreeSha = jsonDecode(commitRes.body)['tree']['sha'] as String;

      // 3. Upload every file as a blob.
      final treeItems = <Map<String, dynamic>>[];
      for (final file in files) {
        final blobRes = await http.post(
          Uri.parse('$base/git/blobs'),
          headers: headers,
          body: jsonEncode({'content': base64Encode(file.value), 'encoding': 'base64'}),
        );
        if (blobRes.statusCode != 201) {
          return GithubPushResult(false, '❌ Failed uploading "${file.key}" [${blobRes.statusCode}]');
        }
        final blobSha = jsonDecode(blobRes.body)['sha'] as String;
        treeItems.add({'path': file.key, 'mode': '100644', 'type': 'blob', 'sha': blobSha});
      }

      // 4. New tree built on top of the base tree.
      final treeRes = await http.post(
        Uri.parse('$base/git/trees'),
        headers: headers,
        body: jsonEncode({'base_tree': baseTreeSha, 'tree': treeItems}),
      );
      if (treeRes.statusCode != 201) {
        return GithubPushResult(false, '❌ Failed building tree [${treeRes.statusCode}]');
      }
      final newTreeSha = jsonDecode(treeRes.body)['sha'] as String;

      // 5. New commit pointing at the new tree.
      final commitCreateRes = await http.post(
        Uri.parse('$base/git/commits'),
        headers: headers,
        body: jsonEncode({
          'message': commitMessage,
          'tree': newTreeSha,
          'parents': [latestCommitSha],
          'author': {'name': authorName, 'email': _placeholderEmail(authorName)},
          'committer': {'name': authorName, 'email': _placeholderEmail(authorName)},
        }),
      );
      if (commitCreateRes.statusCode != 201) {
        return GithubPushResult(false, '❌ Failed creating commit [${commitCreateRes.statusCode}]');
      }
      final newCommitSha = jsonDecode(commitCreateRes.body)['sha'] as String;

      // 6. Fast-forward the branch ref to the new commit.
      final updateRefRes = await http.patch(
        Uri.parse('$base/git/refs/heads/$branch'),
        headers: headers,
        body: jsonEncode({'sha': newCommitSha}),
      );
      if (updateRefRes.statusCode == 200) {
        return GithubPushResult(true, '🚀 Pushed ${files.length} files to $owner/$repo ($branch) in 1 commit.');
      }
      return GithubPushResult(false, '❌ Failed updating branch ref [${updateRefRes.statusCode}]');
    } catch (e) {
      return GithubPushResult(false, '❌ Network Exception: $e');
    }
  }

  /// Best-effort commit-author email so the "author" object is valid even
  /// though only a display name is collected from the user.
  String _placeholderEmail(String name) {
    final slug = name.trim().isEmpty
        ? 'gax-ide'
        : name.trim().toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '-');
    return '$slug@users.noreply.github.com';
  }

  /// Auto-fetches the PAT's own GitHub login, used to pre-fill the push
  /// dialog's "Username" field whenever possible.
  Future<String?> fetchAuthenticatedUsername(String token) async {
    try {
      final res = await http.get(
        Uri.parse('https://api.github.com/user'),
        headers: {'Authorization': 'token $token', 'Accept': 'application/vnd.github.v3+json'},
      );
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        return data['login'] as String?;
      }
      return null;
    } catch (_) {
      return null;
    }
  }
}
