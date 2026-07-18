import 'package:flutter/material.dart';
import 'package:code_text_field/code_text_field.dart';
import '../models/quick_action.dart';

/// Row of quick-insert buttons that sits just above the keyboard —
/// symbols insert at the cursor, Undo/Redo drive the shared
/// UndoHistoryController. Which buttons appear (and in what order) is
/// customized from Settings.
class QuickToolbar extends StatelessWidget {
  final CodeController controller;
  final UndoHistoryController undoController;
  final List<QuickAction> actions;

  const QuickToolbar({
    super.key,
    required this.controller,
    required this.undoController,
    required this.actions,
  });

  void _insertText(String text) {
    final selection = controller.selection;
    final current = controller.text;
    final start = selection.start < 0 ? current.length : selection.start;
    final end = selection.end < 0 ? current.length : selection.end;
    final newText = current.replaceRange(start, end, text);
    controller.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: start + text.length),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (actions.isEmpty) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;

    return Container(
      height: 46,
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: scheme.outlineVariant.withOpacity(0.4)),
      ),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
        itemCount: actions.length,
        separatorBuilder: (_, __) => const SizedBox(width: 6),
        itemBuilder: (context, index) {
          final action = actions[index];

          if (action.isUndo || action.isRedo) {
            return ValueListenableBuilder<UndoHistoryValue>(
              valueListenable: undoController,
              builder: (context, value, _) {
                final enabled = action.isUndo ? value.canUndo : value.canRedo;
                return _ToolbarButton(
                  icon: action.isUndo ? Icons.undo_rounded : Icons.redo_rounded,
                  enabled: enabled,
                  onTap: action.isUndo ? undoController.undo : undoController.redo,
                );
              },
            );
          }

          return _ToolbarButton(
            label: action.label,
            enabled: true,
            onTap: () => _insertText(action.insertText!),
          );
        },
      ),
    );
  }
}

class _ToolbarButton extends StatelessWidget {
  final String? label;
  final IconData? icon;
  final bool enabled;
  final VoidCallback onTap;

  const _ToolbarButton({this.label, this.icon, required this.enabled, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = enabled ? scheme.onSurface : scheme.onSurface.withOpacity(0.3);

    return Material(
      color: scheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: enabled ? onTap : null,
        child: Container(
          constraints: const BoxConstraints(minWidth: 40),
          height: double.infinity,
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: icon != null
              ? Icon(icon, size: 18, color: color)
              : Text(
                  label!,
                  style: TextStyle(fontFamily: 'monospace', fontSize: 16, fontWeight: FontWeight.w600, color: color),
                ),
        ),
      ),
    );
  }
}
