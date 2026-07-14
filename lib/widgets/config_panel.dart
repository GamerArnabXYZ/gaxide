import 'package:flutter/material.dart';

/// GitHub config inputs — soft "glass card" (gradient + border + shadow,
/// no BackdropFilter) so it stays lag-free on low-end hardware.
class ConfigPanel extends StatelessWidget {
  final TextEditingController tokenController;
  final TextEditingController repoController;
  final TextEditingController branchController;
  final TextEditingController pathController;
  final TextEditingController commitController;
  final ValueChanged<String>? onAnyFieldChanged;

  const ConfigPanel({
    super.key,
    required this.tokenController,
    required this.repoController,
    required this.branchController,
    required this.pathController,
    required this.commitController,
    this.onAnyFieldChanged,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            scheme.surfaceContainerHigh.withOpacity(0.85),
            scheme.surfaceContainer.withOpacity(0.55),
          ],
        ),
        border: Border.all(color: Colors.white.withOpacity(0.08)),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.25), blurRadius: 18, offset: const Offset(0, 8)),
        ],
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: EdgeInsets.zero,
          childrenPadding: const EdgeInsets.only(bottom: 12),
          initiallyExpanded: true,
          leading: Icon(Icons.hub_rounded, color: scheme.primary, size: 20),
          title: const Text('GitHub Configuration', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
          children: [
            const SizedBox(height: 8),
            TextField(
              controller: tokenController,
              obscureText: true,
              onChanged: onAnyFieldChanged,
              decoration: const InputDecoration(
                labelText: 'Personal Access Token (PAT)',
                prefixIcon: Icon(Icons.key_rounded, size: 20),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: repoController,
              onChanged: onAnyFieldChanged,
              decoration: const InputDecoration(
                labelText: 'Repository',
                hintText: 'username/repo-name',
                prefixIcon: Icon(Icons.folder_special_rounded, size: 20),
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: branchController,
                    onChanged: onAnyFieldChanged,
                    decoration: const InputDecoration(labelText: 'Branch', hintText: 'main'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  flex: 2,
                  child: TextField(
                    controller: pathController,
                    onChanged: onAnyFieldChanged,
                    decoration: const InputDecoration(labelText: 'File Path', hintText: 'index.js'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            TextField(
              controller: commitController,
              decoration: const InputDecoration(labelText: 'Commit Message (optional)'),
            ),
          ],
        ),
      ),
    );
  }
}
