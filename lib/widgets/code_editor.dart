import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:code_text_field/code_text_field.dart';
import 'package:flutter_highlight/themes/atom-one-dark.dart';
import '../models/editor_language.dart';
import '../services/prefs_service.dart';
import '../services/theme_controller.dart';

/// Editor surface: language dropdown header, Find & Replace bar (toggled
/// from the header), and the syntax-highlighted code area itself.
///
/// Line numbers are NOT rendered via CodeField's built-in gutter — that
/// feature has a real bug in this package where multi-digit line numbers
/// (10, 11, 12...) split one digit per row instead of showing as one
/// number. This gutter is built from scratch instead: a plain TextField
/// (still syntax-highlighted, since that comes from CodeController's own
/// buildTextSpan + the CodeTheme ancestor — nothing to do with CodeField)
/// next to a manually-drawn number column.
///
/// The gutter and the code column share ONE vertical ScrollController —
/// they are two children of the SAME scrollable Row, not two separately
/// scrolled widgets kept in sync by a listener. An earlier version tried
/// mirroring one controller's offset onto a second, independent one; any
/// tiny per-line height mismatch between the two (font-metric rounding,
/// float drift) compounds over hundreds of lines until the gutter's own
/// max-scroll-extent is reached before the code column's, so the numbers
/// visibly stop climbing while the code keeps scrolling. Sharing a single
/// controller makes that class of bug structurally impossible — there is
/// only one scroll position, so both sides always move by construction.
///
/// Only vertical scrolling is shared; horizontal scrolling (for long
/// lines, which never soft-wrap) stays local to the code column only, via
/// its own nested horizontal scroll view, so the numbers don't slide
/// sideways with the code.
///
/// Pinch-to-zoom changes the font size (persisted across sessions) using a
/// raw `Listener` — NOT a GestureDetector/InteractiveViewer — since those
/// claim the gesture arena and would break normal single-finger scrolling
/// and text selection. `Listener` only observes pointer events without
/// consuming them, so it layers on top of everything else safely.
///
/// The editor's code font itself is user-selectable from Settings (must
/// stay monospace so columns/line numbers align) — read live from
/// [ThemeController] via an AnimatedBuilder, same pattern as the app's
/// color theme.
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

  final _verticalController = ScrollController();

  final Map<int, Offset> _activePointers = {};
  double _pinchStartDistance = 0;
  double _pinchStartFontSize = 14;

  // ---- Find & Replace ----
  bool _showFind = false;
  final _findController = TextEditingController();
  final _replaceController = TextEditingController();
  final _findFocusNode = FocusNode();
  List<int> _matches = [];
  int _currentMatch = -1;
  // The text _matches was computed against. Lets us tell "the user edited
  // the document while Find was open" (matches are now stale — offsets no
  // longer point at the right characters, or may even exceed the new,
  // shorter text's length) apart from "our own code just moved the
  // selection to highlight a match" (which also fires the controller's
  // listeners, but the text itself didn't change).
  String? _lastSearchedText;

  String get _editorFontFamily => GoogleFonts.getFont(ThemeController.instance.editorFont).fontFamily!;

  TextStyle get _codeStyle => GoogleFonts.getFont(
        ThemeController.instance.editorFont,
        fontSize: _fontSize,
        height: _lineHeightMultiplier,
      );
  StrutStyle get _strut => StrutStyle(
        fontFamily: _editorFontFamily,
        fontSize: _fontSize,
        height: _lineHeightMultiplier,
        forceStrutHeight: true,
      );

  @override
  void initState() {
    super.initState();
    _loadFontSize();
    _findController.addListener(_runSearch);
    widget.controller.addListener(_onControllerChanged);
  }

  @override
  void didUpdateWidget(covariant CodeEditorView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onControllerChanged);
      widget.controller.addListener(_onControllerChanged);
    }
  }

  /// Fires on every controller change — including ones WE cause by
  /// setting `.selection` to highlight a match. Only re-searches when the
  /// actual TEXT differs from what was last searched, so this can't loop
  /// forever (selection-only changes leave the text, and therefore this
  /// check, unchanged) and so a plain cursor move never nukes the results.
  void _onControllerChanged() {
    if (!_showFind || _findController.text.isEmpty) return;
    if (widget.controller.text == _lastSearchedText) return;
    _runSearch();
  }

  Future<void> _loadFontSize() async {
    final size = await _prefsService.loadFontSize();
    if (mounted) setState(() => _fontSize = size);
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

  void _toggleFind() {
    setState(() => _showFind = !_showFind);
    if (_showFind) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _findFocusNode.requestFocus());
    } else {
      setState(() {
        _matches = [];
        _currentMatch = -1;
      });
    }
  }

  void _runSearch() {
    final query = _findController.text;
    _lastSearchedText = widget.controller.text;
    if (query.isEmpty) {
      setState(() {
        _matches = [];
        _currentMatch = -1;
      });
      return;
    }
    final lowerText = widget.controller.text.toLowerCase();
    final lowerQuery = query.toLowerCase();
    final matches = <int>[];
    var start = 0;
    while (true) {
      final idx = lowerText.indexOf(lowerQuery, start);
      if (idx == -1) break;
      matches.add(idx);
      start = idx + lowerQuery.length;
    }
    setState(() {
      _matches = matches;
      _currentMatch = matches.isEmpty ? -1 : 0;
    });
    if (matches.isNotEmpty) _selectMatch(0);
  }

  void _selectMatch(int index) {
    if (_matches.isEmpty) return;
    final wrapped = index % _matches.length;
    final start = _matches[wrapped];
    final len = _findController.text.length;
    if (start < 0 || start + len > widget.controller.text.length) return; // stale offset — bail safely
    widget.controller.selection = TextSelection(baseOffset: start, extentOffset: start + len);
    _scrollToCharOffset(start);
    setState(() => _currentMatch = wrapped);
  }

  void _scrollToCharOffset(int charOffset) {
    if (!_verticalController.hasClients) return;
    final textBefore = widget.controller.text.substring(0, charOffset);
    final lineIndex = '\n'.allMatches(textBefore).length;
    final lineHeight = _fontSize * _lineHeightMultiplier;
    final target = (lineIndex * lineHeight - 120).clamp(0.0, _verticalController.position.maxScrollExtent);
    _verticalController.animateTo(target, duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
  }

  void _nextMatch() {
    if (_matches.isEmpty) return;
    _selectMatch(_currentMatch + 1);
  }

  void _prevMatch() {
    if (_matches.isEmpty) return;
    _selectMatch(_currentMatch - 1 + _matches.length);
  }

  void _replaceCurrent() {
    if (_currentMatch == -1 || _matches.isEmpty || widget.readOnly) return;
    final start = _matches[_currentMatch];
    final query = _findController.text;
    final replacement = _replaceController.text;
    final text = widget.controller.text;
    if (start < 0 || start + query.length > text.length) return; // stale offset — bail safely
    final newText = text.replaceRange(start, start + query.length, replacement);
    widget.controller.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: start + replacement.length),
    );
    _runSearch();
  }

  void _replaceAll() {
    final query = _findController.text;
    if (query.isEmpty || widget.readOnly) return;
    final replacement = _replaceController.text;
    final text = widget.controller.text;
    final regex = RegExp(RegExp.escape(query), caseSensitive: false);
    final count = regex.allMatches(text).length;
    final newText = text.replaceAll(regex, replacement);
    widget.controller.value = TextEditingValue(text: newText, selection: const TextSelection.collapsed(offset: 0));
    setState(() {
      _matches = [];
      _currentMatch = -1;
    });
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Replaced $count occurrence(s)'), duration: const Duration(seconds: 2)),
      );
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onControllerChanged);
    _verticalController.dispose();
    _findController.dispose();
    _replaceController.dispose();
    _findFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AnimatedBuilder(
      // Rebuilds instantly when the editor font is changed in Settings.
      animation: ThemeController.instance,
      builder: (context, _) => _buildBody(scheme),
    );
  }

  Widget _buildBody(ColorScheme scheme) {
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
                IconButton(
                  tooltip: 'Find & Replace',
                  icon: Icon(_showFind ? Icons.close_rounded : Icons.search_rounded, size: 20),
                  visualDensity: VisualDensity.compact,
                  onPressed: _toggleFind,
                ),
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
          if (_showFind) _buildFindReplaceBar(scheme),
          Expanded(
            child: CodeTheme(
              data: CodeThemeData(styles: atomOneDarkTheme),
              child: Listener(
                onPointerDown: _onPointerDown,
                onPointerMove: _onPointerMove,
                onPointerUp: _onPointerUp,
                onPointerCancel: _onPointerUp,
                child: SingleChildScrollView(
                  controller: _verticalController,
                  padding: const EdgeInsets.only(top: 8, bottom: 24),
                  child: IntrinsicHeight(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        SizedBox(
                          width: _gutterWidth,
                          child: Padding(
                            padding: const EdgeInsets.only(right: 10),
                            child: AnimatedBuilder(
                              animation: widget.controller,
                              builder: (context, _) {
                                final lineCount = '\n'.allMatches(widget.controller.text).length + 1;
                                final numbers = List.generate(lineCount, (i) => '${i + 1}').join('\n');
                                return Text(
                                  numbers,
                                  textAlign: TextAlign.right,
                                  style: TextStyle(
                                    fontFamily: _editorFontFamily,
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
                            scrollDirection: Axis.horizontal,
                            padding: const EdgeInsets.only(left: 8),
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
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFindReplaceBar(ColorScheme scheme) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh,
        border: Border(bottom: BorderSide(color: scheme.outlineVariant.withOpacity(0.4))),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _findController,
                  focusNode: _findFocusNode,
                  decoration: const InputDecoration(
                    isDense: true,
                    hintText: 'Find',
                    contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  ),
                  textInputAction: TextInputAction.search,
                  onSubmitted: (_) => _nextMatch(),
                ),
              ),
              const SizedBox(width: 6),
              Text(
                _matches.isEmpty ? '0/0' : '${_currentMatch + 1}/${_matches.length}',
                style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
              ),
              IconButton(
                tooltip: 'Previous',
                icon: const Icon(Icons.keyboard_arrow_up_rounded),
                visualDensity: VisualDensity.compact,
                onPressed: _matches.isEmpty ? null : _prevMatch,
              ),
              IconButton(
                tooltip: 'Next',
                icon: const Icon(Icons.keyboard_arrow_down_rounded),
                visualDensity: VisualDensity.compact,
                onPressed: _matches.isEmpty ? null : _nextMatch,
              ),
            ],
          ),
          if (!widget.readOnly) ...[
            const SizedBox(height: 6),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _replaceController,
                    decoration: const InputDecoration(
                      isDense: true,
                      hintText: 'Replace',
                      contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                TextButton(
                  onPressed: _matches.isEmpty ? null : _replaceCurrent,
                  child: const Text('Replace'),
                ),
                TextButton(
                  onPressed: _findController.text.isEmpty ? null : _replaceAll,
                  child: const Text('All'),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
