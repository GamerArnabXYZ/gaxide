import 'dart:io';
import '../models/git_repo_info.dart';

/// Reads local `.git` metadata directly (plain text files git itself
/// maintains) — no git binary call needed. Powers auto-detection of
/// owner/repo/branch so nothing has to be typed manually per project.
class GitService {
  Future<bool> isGitRepo(String folderPath) => Directory('$folderPath/.git').exists();

  Future<GitRepoInfo?> readRepoInfo(String folderPath) async {
    try {
      final configFile = File('$folderPath/.git/config');
      if (!await configFile.exists()) return null;
      final configContent = await configFile.readAsString();

      final urlMatch = RegExp(r'url\s*=\s*(.+)').firstMatch(configContent);
      if (urlMatch == null) return null;
      final url = urlMatch.group(1)!.trim();

      // Handles both HTTPS (https://github.com/owner/repo.git) and
      // SSH (git@github.com:owner/repo.git) remote URL formats.
      final repoMatch = RegExp(r'github\.com[:/]+([^/]+)/([^/.\s]+)').firstMatch(url);
      if (repoMatch == null) return null;

      String branch = 'main';
      final headFile = File('$folderPath/.git/HEAD');
      if (await headFile.exists()) {
        final headContent = (await headFile.readAsString()).trim();
        final branchMatch = RegExp(r'refs/heads/(.+)$').firstMatch(headContent);
        if (branchMatch != null) branch = branchMatch.group(1)!;
      }

      return GitRepoInfo(owner: repoMatch.group(1)!, repo: repoMatch.group(2)!, branch: branch);
    } catch (_) {
      return null;
    }
  }

  /// Walks upward from any file/folder path to find the nearest containing
  /// git repo root. Stops at [stopAtPath] (the storage root) to avoid an
  /// endless climb.
  Future<String?> findNearestGitRoot(String startPath, {required String stopAtPath}) async {
    var current = startPath;
    while (true) {
      if (await isGitRepo(current)) return current;
      if (current == stopAtPath) return null;
      final idx = current.lastIndexOf('/');
      if (idx <= 0) return null;
      final parent = current.substring(0, idx);
      if (parent == current) return null;
      current = parent;
    }
  }
}
