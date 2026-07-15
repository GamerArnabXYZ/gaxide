import 'package:flutter/material.dart';

/// GitHub PAT input — the only global setting left. Repo & branch are
/// auto-detected per-project from each folder's own `.git` metadata.
/// Soft "glass card" look (gradient + border + shadow, no BackdropFilter)
/// so it stays lag-free on low-end hardware.
class ConfigPanel extends StatelessWidget {
  final TextEditingController tokenController;
  final ValueChanged<String>? onChanged;

  const ConfigPanel({super.key, required this.tokenController, this.onChanged});

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
              const Text('GitHub Access', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
            ],
          ),
          const SizedBox(height: 16),
          TextField(
            controller: tokenController,
            obscureText: true,
            onChanged: onChanged,
            decoration: const InputDecoration(
              labelText: 'Personal Access Token (PAT)',
              prefixIcon: Icon(Icons.key_rounded, size: 20),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'That\'s it — repo name & branch are auto-detected from every '
            'project\'s own .git folder. Just clone/init your repos normally '
            'and GAX IDE will recognize them automatically.',
            style: TextStyle(fontSize: 11.5, color: scheme.onSurfaceVariant.withOpacity(0.8)),
          ),
        ],
      ),
    );
  }
}
