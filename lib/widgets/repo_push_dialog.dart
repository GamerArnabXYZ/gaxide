import 'package:flutter/material.dart';
import '../services/file_service.dart';
import '../services/git_service.dart';
import '../services/github_service.dart';
import '../services/prefs_service.dart';

const _stickyCommitTag = 'Updated/Modified by GAX IDE';

/// Push dialog for ANY folder — opens INSTANTLY (no network wait). Repo &
/// branch are auto-filled from local `.git` metadata (fast, no network).
/// The GitHub username is fetched in the background after the dialog is
/// already visible and fills in once it arrives, so opening never feels
/// slow. The commit message tag is sticky — always appended, never
/// removable from the field itself.
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

  // ---- Fast, local-only auto-detection (no network) — safe to await ----
  String autoRepo = '';
  String autoBranch = 'main';
  final gitRoot = await gitService.findNearestGitRoot(folderPath, stopAtPath: FileService.rootStoragePath);
  if (gitRoot != null) {
    final repoInfo = await gitService.readRepoInfo(gitRoot);
    if (repoInfo != null) {
      autoRepo = repoInfo.fullName;
      autoBranch = repoInfo.branch;
    }
  }

  if (!context.mounted) return;

  final repoController = TextEditingController(text: autoRepo);
  final branchController = TextEditingController(text: autoBranch);
  final usernameController = TextEditingController(text: 'GAX IDE');
  final commitController = TextEditingController();

  bool isPushing = false;
  bool usernameEditedByUser = false;
  bool usernameFetchStarted = false;
  String progressText = '';
  String? errorText;

  // Kick off the (network) username lookup AFTER the dialog opens — never
  // block the dialog's appearance on a network round-trip. Runs exactly once.
  void fetchUsernameInBackground(void Function(void Function()) setDialogState) {
    githubService.fetchAuthenticatedUsername(config.token).then((login) {
      if (login != null && login.isNotEmpty && !usernameEditedByUser) {
        setDialogState(() => usernameController.text = login);
      }
    });
  }

  await showDialog(
    context: context,
    barrierDismissible: !isPushing,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setDialogState) {
        if (!usernameFetchStarted) {
          usernameFetchStarted = true;
          fetchUsernameInBackground(setDialogState);
        }

        return AlertDialog(
          title: const Text('Push to GitHub'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Theme.of(ctx).colorScheme.surfaceContainerHigh,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    'This folder will be pushed:\n$folderPath',
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
                const SizedBox(height: 12),
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
                  onChanged: (_) => usernameEditedByUser = true,
                  decoration: const InputDecoration(labelText: 'Username', hintText: 'GAX IDE'),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: commitController,
                  enabled: !isPushing,
                  decoration: const InputDecoration(
                    labelText: 'Commit Message (optional)',
                    hintText: 'e.g. fixed login bug',
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  '"($_stickyCommitTag)" is always added at the end.',
                  style: TextStyle(fontSize: 11, color: Colors.grey),
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

                      final ignoreDirs = (await prefsService.loadPerformancePrefs()).ignoreDirs;
                      final files = await fileService.collectFilesForPush(folderPath, ignoreDirs: ignoreDirs);
                      setDialogState(() => progressText = 'Uploading ${files.length} files...');

                      final userCommitMsg = commitController.text.trim();
                      final finalCommitMessage =
                          userCommitMsg.isEmpty ? _stickyCommitTag : '$userCommitMsg ($_stickyCommitTag)';

                      final result = await githubService.pushFolder(
                        token: config.token,
                        owner: repoParts[0],
                        repo: repoParts[1],
                        branch: branchController.text.trim(),
                        files: files,
                        commitMessage: finalCommitMessage,
                        authorName:
                            usernameController.text.trim().isEmpty ? 'GAX IDE' : usernameController.text.trim(),
                      );

                      if (ctx.mounted) Navigator.pop(ctx);
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(result.message)));
                      }
                    },
            ),
          ],
        );
      },
    ),
  );
}
