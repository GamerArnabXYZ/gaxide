import 'package:flutter/material.dart';
import 'package:code_text_field/code_text_field.dart';
import 'package:flutter_highlight/themes/atom-one-dark.dart';
import '../models/editor_language.dart';

/// Editor surface: language dropdown header + syntax-highlighted code area.
///
/// Line numbers are NOT rendered via CodeField's built-in gutter — that
/// feature has a real bug in this package where multi-digit line numbers
/// (10, 11, 12...) split one digit per row instead of showing as one
/// number. This gutter is built from scratch instead: a plain TextField
/// (still syntax-highlighted, since that comes from CodeController's own
/// buildTextSpan + the CodeTheme ancestor — nothing to do with CodeField)
/// next to a manually-drawn number column.
///
/// The gutter is a single multi-line Text widget ("1\n2\n3...") using the
/// EXACT SAME TextStyle + StrutStyle as the code TextField — not a column
/// of fixed-height boxes. Two different rendering systems (a hand-sized
/// box grid vs. the text engine that actually lays out the code) can each
/// compute a slightly different height per line — especially for blank
/// lines — and that tiny gap compounds over many lines into visible drift.
/// Using the identical text engine + identical style for both sides means
/// whatever Flutter decides a line's height is, both columns agree on it.
///
/// Lines never soft-wrap (long lines scroll sideways instead), so every
/// logical line is guaranteed to be exactly one row tall in both columns.
/// The two columns scroll together via an explicit listener that mirrors
/// the code column's offset onto the (touch-disabled) gutter column — just
/// sharing one ScrollController between two Scrollables does NOT keep them
/// in sync during a drag, so this manual mirroring is required.
class CodeEditorView extends StatefulWidget {
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
  State<CodeEditorView> createState() => _CodeEditorViewState();
}

class _CodeEditorViewState extends State<CodeEditorView> {
  static const double _fontSize = 14;
  static const double _lineHeightMultiplier = 1.5;
  static const double _gutterWidth = 46;
  static const double _codeMinWidth = 2000; // generous so lines never soft-wrap

  static const _codeStyle = TextStyle(fontFamily: 'monospace', fontSize: _fontSize, height: _lineHeightMultiplier);
  static const _strut = StrutStyle(fontSize: _fontSize, height: _lineHeightMultiplier, forceStrutHeight: true);

  final _codeScrollController = ScrollController();
  final _gutterScrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    // The gutter never receives touch (NeverScrollableScrollPhysics) — it
    // only ever moves by mirroring the code column's real scroll offset.
    _codeScrollController.addListener(_mirrorScrollToGutter);
  }

  void _mirrorScrollToGutter() {
    if (!_gutterScrollController.hasClients) return;
    final target = _codeScrollController.offset;
    final max = _gutterScrollController.position.maxScrollExtent;
    final min = _gutterScrollController.position.minScrollExtent;
    _gutterScrollController.jumpTo(target.clamp(min, max));
  }

  @override
  void dispose() {
    _codeScrollController.removeListener(_mirrorScrollToGutter);
    _codeScrollController.dispose();
    _gutterScrollController.dispose();
    super.dispose();
  }

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
                    value: widget.currentLanguage,
                    isDense: true,
                    borderRadius: BorderRadius.circular(12),
                    items: EditorLanguage.values
                        .map((lang) => DropdownMenuItem(value: lang, child: Text(lang.label)))
                        .toList(),
                    onChanged: (lang) {
                      if (lang != null) widget.onLanguageChanged(lang);
                    },
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: CodeTheme(
              data: CodeThemeData(styles: atomOneDarkTheme),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(
                    width: _gutterWidth,
                    child: SingleChildScrollView(
                      controller: _gutterScrollController,
                      physics: const NeverScrollableScrollPhysics(),
                      padding: const EdgeInsets.only(top: 8, right: 10),
                      child: AnimatedBuilder(
                        animation: widget.controller,
                        builder: (context, _) {
                          final lineCount = '\n'.allMatches(widget.controller.text).length + 1;
                          final numbers = List.generate(lineCount, (i) => '${i + 1}').join('\n');
                          return Text(
                            numbers,
                            textAlign: TextAlign.right,
                            style: TextStyle(
                              fontFamily: 'monospace',
                              fontSize: _fontSize,
                              height: _lineHeightMultiplier,
                              color: scheme.onSurfaceVariant.withOpacity(0.5),
                            ),
                            strutStyle: _strut,
                          );
                        },
                      ),
                    ),
                  ),
                  Container(width: 1, color: scheme.outlineVariant.withOpacity(0.3)),
                  Expanded(
                    child: SingleChildScrollView(
                      controller: _codeScrollController,
                      padding: const EdgeInsets.only(top: 8, left: 8, bottom: 24),
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: SizedBox(
                          width: _codeMinWidth,
                          child: TextField(
                            controller: widget.controller,
                            maxLines: null,
                            keyboardType: TextInputType.multiline,
                            textInputAction: TextInputAction.newline,
                            autocorrect: false,
                            enableSuggestions: false,
                            style: _codeStyle,
                            strutStyle: _strut,
                            cursorColor: scheme.primary,
                            decoration: const InputDecoration(
                              border: InputBorder.none,
                              isDense: true,
                              contentPadding: EdgeInsets.zero,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
