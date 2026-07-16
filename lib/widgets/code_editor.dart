import 'package:flutter/material.dart';
import 'package:code_text_field/code_text_field.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_highlight/themes/atom-one-dark.dart';
import '../models/editor_language.dart';

/// Editor surface: language dropdown header + syntax-highlighted CodeField.
class CodeEditorView extends StatelessWidget {
  final CodeController controller;
  final EditorLanguage currentLanguage;
  final ValueChanged<EditorLanguage> onLanguageChanged;

  const CodeEditorView({
    super.key,
    required this.controller,
    required this.currentLanguage,
    required this.onLanguageChanged,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: scheme.outlineVariant.withOpacity(0.4)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHigh,
              border: Border(bottom: BorderSide(color: scheme.outlineVariant.withOpacity(0.4))),
            ),
            child: Row(
              children: [
                Icon(Icons.code_rounded, size: 18, color: scheme.primary),
                const SizedBox(width: 8),
                const Text('Language', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                const Spacer(),
                DropdownButtonHideUnderline(
                  child: DropdownButton<EditorLanguage>(
                    value: currentLanguage,
                    isDense: true,
                    borderRadius: BorderRadius.circular(12),
                    items: EditorLanguage.values
                        .map((lang) => DropdownMenuItem(value: lang, child: Text(lang.label)))
                        .toList(),
                    onChanged: (lang) {
                      if (lang != null) onLanguageChanged(lang);
                    },
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(4),
              child: CodeTheme(
                data: CodeThemeData(styles: atomOneDarkTheme),
                child: CodeField(
                  controller: controller,
                  expands: true,
                  textStyle: GoogleFonts.firaCode(fontSize: 14, height: 1.5),
                  background: Colors.transparent,
                  lineNumberStyle: LineNumberStyle(
                    textStyle: TextStyle(color: scheme.onSurfaceVariant.withOpacity(0.5), fontSize: 13),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
