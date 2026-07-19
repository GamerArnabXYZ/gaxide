import 'package:flutter/material.dart';
import 'package:code_text_field/code_text_field.dart';
import 'package:flutter_highlight/themes/atom-one-dark.dart';
import '../models/editor_language.dart';
import '../services/prefs_service.dart';

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
/// of fixed-height boxes — so both sides always agree on line height.
///
/// Lines never soft-wrap (long lines scroll sideways instead), so every
/// logical line is guaranteed to be exactly one row tall in both columns.
/// The two columns scroll together via an explicit listener that mirrors
/// the code column's offset onto the (touch-disabled) gutter column.
///
/// Pinch-to-zoom changes the font size (persisted across sessions) using a
/// raw `Listener` — NOT a GestureDetector/InteractiveViewer — since those
/// claim the gesture arena and would break normal single-finger scrolling
/// and text selection. `Listener` only observes pointer events without
/// consuming them, so it layers on top of everything else safely.
class CodeEditorView extends StatefulWidget {
  final CodeController controller;
  final EditorLanguage currentLanguage;
  final ValueChanged<EditorLanguage> onLanguageChanged;
  final UndoHistoryController? undoController;
  final bool readOnly;

  const CodeEditorView({
    super.key,
    required this.controller,
    required this.currentLanguage,
    required this.onLanguageChanged,
    this.undoController,
    this.readOnly = false,
  });

  @override
  State<CodeEditorView> createState() => _CodeEditorViewState();
}

class _CodeEditorViewState extends State<CodeEditorView> {
  static const double _minFontSize = 2;
  static const double _maxFontSize = 30;
  static const double _lineHeightMultiplier = 1.5;
  static const double _gutterWidth = 46;
  static const double _codeMinWidth = 2000; // generous so lines never soft-wrap

  final _prefsService = PrefsService();
  double _fontSize = 14;

  final _codeScrollController = ScrollController();
  final _gutterScrollController = ScrollController();

  final Map<int, Offset> _activePointers = {};
  double _pinchStartDistance = 0;
  double _pinchStartFontSize = 14;

  TextStyle get _codeStyle => TextStyle(fontFamily: 'monospace', fontSize: _fontSize, height: _lineHeightMultiplier);
  StrutStyle get _strut =>
      StrutStyle(fontSize: _fontSize, height: _lineHeightMultiplier, forceStrutHeight: true);

  @override
  void initState() {
    super.initState();
    _codeScrollController.addListener(_mirrorScrollToGutter);
    _loadFontSize();
  }

  Future<void> _loadFontSize() async {
    final size = await _prefsService.loadFontSize();
    if (mounted) setState(() => _fontSize = size);
  }

  void _mirrorScrollToGutter() {
    if (!_gutterScrollController.hasClients) return;
    final target = _codeScrollController.offset;
    final maxExtent = _gutterScrollController.position.maxScrollExtent;
    final minExtent = _gutterScrollController.position.minScrollExtent;
    _gutterScrollController.jumpTo(target.clamp(minExtent, maxExtent));
  }

  void _onPointerDown(PointerDownEvent event) {
    _activePointers[event.pointer] = event.position;
    if (_activePointers.length == 2) {
      final points = _activePointers.values.toList();
      _pinchStartDistance = (points[0] - points[1]).distance;
      _pinchStartFontSize = _fontSize;
    }
  }

  void _onPointerMove(PointerMoveEvent event) {
    if (!_activePointers.containsKey(event.pointer)) return;
    _activePointers[event.pointer] = event.position;
    if (_activePointers.length == 2 && _pinchStartDistance > 10) {
      final points = _activePointers.values.toList();
      final currentDistance = (points[0] - points[1]).distance;
      final scale = currentDistance / _pinchStartDistance;
      final newSize = (_pinchStartFontSize * scale).clamp(_minFontSize, _maxFontSize);
      if ((newSize - _fontSize).abs() > 0.3) {
        setState(() => _fontSize = newSize);
      }
    }
  }

  void _onPointerUp(PointerEvent event) {
    _activePointers.remove(event.pointer);
    if (_activePointers.length < 2 && _pinchStartDistance > 0) {
      _pinchStartDistance = 0;
      _prefsService.saveFontSize(_fontSize);
    }
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
                    onChanged: widget.readOnly
                        ? null
                        : (lang) {
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
              child: Listener(
                onPointerDown: _onPointerDown,
                onPointerMove: _onPointerMove,
                onPointerUp: _onPointerUp,
                onPointerCancel: _onPointerUp,
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
                              undoController: widget.undoController,
                              maxLines: null,
                              readOnly: widget.readOnly,
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
          ),
        ],
      ),
    );
  }
}
