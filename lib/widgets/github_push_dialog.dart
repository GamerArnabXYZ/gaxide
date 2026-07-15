import 'package:flutter/material.dart';
import '../services/github_service.dart';
import '../services/prefs_service.dart';

/// Shared "Push to GitHub" dialog — used from both the File Manager
/// (quick push without opening the editor) and the Editor screen.
Future<void> showGithubPushDialog(
  BuildContext context, {
  required String content,
  required String suggestedRepoPath,
}) async {
  final prefsService = PrefsService();
  final githubService = GithubService();
  final config = await prefsService.load();

  if (!context.mounted) return;

  if (config.token.isEmpty || config.repo.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('⚠️ Set up GitHub Token & Repo in Settings first.')),
    );
    return;
  }

  final repoPathController = TextEditingController(text: suggestedRepoPath);
  final branchController = TextEditingController(text: config.branch);
  final commitController = TextEditingController();
  bool isPushing = false;

  await showDialog(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setDialogState) => AlertDialog(
        title: const Text('Push to GitHub'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: repoPathController,
              decoration: const InputDecoration(labelText: 'Path in Repo'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: branchController,
              decoration: const InputDecoration(labelText: 'Branch', hintText: 'main'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: commitController,
              decoration: const InputDecoration(labelText: 'Commit Message (optional)'),
            ),
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
                    setDialogState(() => isPushing = true);
                    final result = await githubService.pushFile(
                      token: config.token,
                      repo: config.repo,
                      filePath: repoPathController.text.trim(),
                      branch: branchController.text.trim(),
                      content: content,
                      commitMessage: commitController.text.trim().isEmpty
                          ? 'Update via GAX IDE'
                          : commitController.text.trim(),
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
