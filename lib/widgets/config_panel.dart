import 'package:flutter/material.dart';

/// GitHub defaults form — lives inside the dedicated Settings screen now.
/// Soft "glass card" look (gradient + border + shadow, no BackdropFilter)
/// so it stays lag-free on low-end hardware.
class ConfigPanel extends StatelessWidget {
  final TextEditingController tokenController;
  final TextEditingController repoController;
  final TextEditingController branchController;
  final ValueChanged<String>? onAnyFieldChanged;

  const ConfigPanel({
    super.key,
    required this.tokenController,
    required this.repoController,
    required this.branchController,
    this.onAnyFieldChanged,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(16),
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.hub_rounded, color: scheme.primary, size: 20),
              const SizedBox(width: 8),
              const Text('GitHub Configuration', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
            ],
          ),
          const SizedBox(height: 16),
          TextField(
            controller: tokenController,
            obscureText: true,
            onChanged: onAnyFieldChanged,
            decoration: const InputDecoration(
              labelText: 'Personal Access Token (PAT)',
              prefixIcon: Icon(Icons.key_rounded, size: 20),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: repoController,
            onChanged: onAnyFieldChanged,
            decoration: const InputDecoration(
              labelText: 'Repository',
              hintText: 'username/repo-name',
              prefixIcon: Icon(Icons.folder_special_rounded, size: 20),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: branchController,
            onChanged: onAnyFieldChanged,
            decoration: const InputDecoration(
              labelText: 'Default Branch',
              hintText: 'main',
              prefixIcon: Icon(Icons.alt_route_rounded, size: 20),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'Used as defaults whenever you push a file from the Editor or File Manager.',
            style: TextStyle(fontSize: 11.5, color: scheme.onSurfaceVariant.withOpacity(0.8)),
          ),
        ],
      ),
    );
  }
}
