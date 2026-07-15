import 'package:flutter/material.dart';
import '../services/file_service.dart';
import '../services/git_service.dart';
import '../services/github_service.dart';
import '../services/prefs_service.dart';

/// Push dialog for a whole git-repo folder — owner/repo auto-detected from
/// `.git/config`, branch from `.git/HEAD`. One tap = one atomic commit of
/// every trackable file in that project.
Future<void> showRepoPushDialog(BuildContext context, {required String folderPath}) async {
  final prefsService = PrefsService();
  final gitService = GitService();
  final fileService = FileService();
  final githubService = GithubService();

  final config = await prefsService.load();
  if (!context.mounted) return;

  if (config.token.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('⚠️ Set up your GitHub Token in Settings first.')),
    );
    return;
  }

  final repoInfo = await gitService.readRepoInfo(folderPath);
  if (!context.mounted) return;

  if (repoInfo == null) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('❌ Could not read remote "origin" from .git/config.')),
    );
    return;
  }

  final branchController = TextEditingController(text: repoInfo.branch);
  final commitController = TextEditingController();
  bool isPushing = false;
  String progressText = '';

  await showDialog(
    context: context,
    barrierDismissible: !isPushing,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setDialogState) => AlertDialog(
        title: const Text('Push to GitHub'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.hub_rounded, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(repoInfo.fullName, style: const TextStyle(fontWeight: FontWeight.bold)),
                ),
              ],
            ),
            const SizedBox(height: 14),
            TextField(
              controller: branchController,
              enabled: !isPushing,
              decoration: const InputDecoration(labelText: 'Branch'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: commitController,
              enabled: !isPushing,
              decoration: const InputDecoration(labelText: 'Commit Message (optional)'),
            ),
            if (isPushing) ...[
              const SizedBox(height: 14),
              Text(progressText, style: const TextStyle(fontSize: 12)),
            ],
          ],
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
                    setDialogState(() {
                      isPushing = true;
                      progressText = 'Collecting files...';
                    });

                    final files = await fileService.collectFilesForPush(folderPath);
                    setDialogState(() => progressText = 'Uploading ${files.length} files...');

                    final result = await githubService.pushFolder(
                      token: config.token,
                      owner: repoInfo.owner,
                      repo: repoInfo.repo,
                      branch: branchController.text.trim(),
                      files: files,
                      commitMessage:
                          commitController.text.trim().isEmpty ? 'Update via GAX IDE' : commitController.text.trim(),
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
