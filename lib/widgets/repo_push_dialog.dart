import 'package:flutter/material.dart';
import '../services/file_service.dart';
import '../services/git_service.dart';
import '../services/github_service.dart';
import '../services/prefs_service.dart';

/// Push dialog for ANY folder — not just detected git repos. Whatever can
/// be auto-detected is auto-filled (repo/branch from .git if present, push
/// path from the folder's position inside that repo, username from the
/// token's own GitHub account); everything stays editable so it also works
/// for plain folders with no .git at all.
Future<void> showRepoPushDialog(BuildContext context, {required String folderPath}) async {
  final prefsService = PrefsService();
  final gitService = GitService();
  final fileService = FileService();
  final githubService = GithubService();

  final config = await prefsService.loadConfig();
  if (!context.mounted) return;

  if (config.token.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('⚠️ Set up your GitHub Token in Settings first.')),
    );
    return;
  }

  // ---- Auto-fetch whatever is possible ----
  final gitRoot = await gitService.findNearestGitRoot(folderPath, stopAtPath: FileService.rootStoragePath);
  String autoRepo = '';
  String autoBranch = 'main';
  String autoPushPath = '';
  if (gitRoot != null) {
    final repoInfo = await gitService.readRepoInfo(gitRoot);
    if (repoInfo != null) {
      autoRepo = repoInfo.fullName;
      autoBranch = repoInfo.branch;
    }
    if (folderPath != gitRoot && folderPath.startsWith('$gitRoot/')) {
      autoPushPath = folderPath.substring(gitRoot.length + 1);
    }
  }
  final autoUsername = await githubService.fetchAuthenticatedUsername(config.token);

  if (!context.mounted) return;

  final pathController = TextEditingController(text: autoPushPath);
  final repoController = TextEditingController(text: autoRepo);
  final branchController = TextEditingController(text: autoBranch);
  final usernameController = TextEditingController(text: autoUsername ?? 'GAX IDE');
  final commitController = TextEditingController(text: 'Updated/Modified by GAX IDE');

  bool isPushing = false;
  String progressText = '';
  String? errorText;

  await showDialog(
    context: context,
    barrierDismissible: !isPushing,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setDialogState) => AlertDialog(
        title: const Text('Push to GitHub'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: pathController,
                enabled: !isPushing,
                decoration: const InputDecoration(
                  labelText: 'Push Path (in repo)',
                  hintText: 'blank = repo root',
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: repoController,
                enabled: !isPushing,
                decoration: const InputDecoration(labelText: 'Repo', hintText: 'username/repo-name'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: branchController,
                enabled: !isPushing,
                decoration: const InputDecoration(labelText: 'Branch', hintText: 'main'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: usernameController,
                enabled: !isPushing,
                decoration: const InputDecoration(labelText: 'Username', hintText: 'GAX IDE'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: commitController,
                enabled: !isPushing,
                decoration: const InputDecoration(labelText: 'Commit Message'),
              ),
              if (errorText != null) ...[
                const SizedBox(height: 10),
                Text(errorText!, style: const TextStyle(color: Colors.redAccent, fontSize: 12)),
              ],
              if (isPushing) ...[
                const SizedBox(height: 14),
                Text(progressText, style: const TextStyle(fontSize: 12)),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: isPushing ? null : () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton.icon(
            icon: isPushing
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.cloud_upload_rounded, size: 18),
            label: Text(isPushing ? 'Pushing...' : 'Push'),
            onPressed: isPushing
                ? null
                : () async {
                    final repoParts = repoController.text.trim().split('/');
                    if (repoParts.length != 2 || repoParts[0].isEmpty || repoParts[1].isEmpty) {
                      setDialogState(() => errorText = 'Repo must look like username/repo-name');
                      return;
                    }
                    if (branchController.text.trim().isEmpty) {
                      setDialogState(() => errorText = 'Branch is required');
                      return;
                    }

                    setDialogState(() {
                      errorText = null;
                      isPushing = true;
                      progressText = 'Collecting files...';
                    });

                    final files = await fileService.collectFilesForPush(folderPath);
                    final pushPrefix = pathController.text.trim();
                    final prefixedFiles = files
                        .map((e) => MapEntry(pushPrefix.isEmpty ? e.key : '$pushPrefix/${e.key}', e.value))
                        .toList();

                    setDialogState(() => progressText = 'Uploading ${prefixedFiles.length} files...');

                    final result = await githubService.pushFolder(
                      token: config.token,
                      owner: repoParts[0],
                      repo: repoParts[1],
                      branch: branchController.text.trim(),
                      files: prefixedFiles,
                      commitMessage: commitController.text.trim().isEmpty
                          ? 'Updated/Modified by GAX IDE'
                          : commitController.text.trim(),
                      authorName: usernameController.text.trim().isEmpty ? 'GAX IDE' : usernameController.text.trim(),
                    );

                    if (ctx.mounted) Navigator.pop(ctx);
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(result.message)));
                    }
                  },
          ),
        ],
      ),
    ),
  );
}
