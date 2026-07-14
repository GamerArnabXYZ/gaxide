import 'package:flutter/material.dart';

/// Bottom status/log strip — shows push/save/open results.
class StatusLogPanel extends StatelessWidget {
  final String status;
  const StatusLogPanel({super.key, required this.status});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh.withOpacity(0.7),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withOpacity(0.06)),
      ),
      child: Text(
        status,
        style: TextStyle(fontFamily: 'monospace', fontSize: 12, color: scheme.onSurfaceVariant),
        maxLines: 3,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}
