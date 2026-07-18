/// Catalog of quick-insert buttons for the editor's toolbar (sits just
/// above the keyboard). Symbol actions insert text at the cursor; Undo/Redo
/// are special actions with no insertable text of their own.
enum QuickAction {
  tab,
  braceOpen,
  braceClose,
  parenOpen,
  parenClose,
  bracketOpen,
  bracketClose,
  semicolon,
  colon,
  equals,
  quoteDouble,
  quoteSingle,
  lessThan,
  greaterThan,
  slash,
  backslash,
  pipe,
  ampersand,
  bang,
  minus,
  plus,
  star,
  hash,
  underscore,
  comma,
  dot,
  undo,
  redo,
}

extension QuickActionX on QuickAction {
  /// Sensible starting set shown before the user customizes anything in Settings.
  static const List<QuickAction> defaultToolbar = [
    QuickAction.tab,
    QuickAction.braceOpen,
    QuickAction.braceClose,
    QuickAction.parenOpen,
    QuickAction.parenClose,
    QuickAction.semicolon,
    QuickAction.equals,
    QuickAction.quoteDouble,
    QuickAction.lessThan,
    QuickAction.greaterThan,
    QuickAction.undo,
    QuickAction.redo,
  ];

  /// Parses a space-separated string of labels (e.g. "Tab { } ( ) ; Undo")
  /// typed by the user in Settings into an ordered, de-duplicated action
  /// list. Unrecognized tokens are silently skipped.
  static List<QuickAction> parseFromInput(String input) {
    final tokens = input.trim().split(RegExp(r'\s+')).where((t) => t.isNotEmpty);
    final result = <QuickAction>[];
    for (final token in tokens) {
      final match = _matchToken(token);
      if (match != null && !result.contains(match)) {
        result.add(match);
      }
    }
    return result;
  }

  static QuickAction? _matchToken(String token) {
    final lower = token.toLowerCase();
    for (final action in QuickAction.values) {
      if (action.label.toLowerCase() == lower) return action;
    }
    return null;
  }

  /// The reverse of [parseFromInput] — turns the current list back into the
  /// space-separated string shown/edited in the Settings input box.
  static String toInputString(List<QuickAction> actions) => actions.map((a) => a.label).join(' ');

  /// All recognizable tokens, for the helper caption in Settings.
  static String get catalogHint => QuickAction.values.map((a) => a.label).join(' ');

  String get label {
    switch (this) {
      case QuickAction.tab:
        return 'Tab';
      case QuickAction.braceOpen:
        return '{';
      case QuickAction.braceClose:
        return '}';
      case QuickAction.parenOpen:
        return '(';
      case QuickAction.parenClose:
        return ')';
      case QuickAction.bracketOpen:
        return '[';
      case QuickAction.bracketClose:
        return ']';
      case QuickAction.semicolon:
        return ';';
      case QuickAction.colon:
        return ':';
      case QuickAction.equals:
        return '=';
      case QuickAction.quoteDouble:
        return '"';
      case QuickAction.quoteSingle:
        return "'";
      case QuickAction.lessThan:
        return '<';
      case QuickAction.greaterThan:
        return '>';
      case QuickAction.slash:
        return '/';
      case QuickAction.backslash:
        return r'\';
      case QuickAction.pipe:
        return '|';
      case QuickAction.ampersand:
        return '&';
      case QuickAction.bang:
        return '!';
      case QuickAction.minus:
        return '-';
      case QuickAction.plus:
        return '+';
      case QuickAction.star:
        return '*';
      case QuickAction.hash:
        return '#';
      case QuickAction.underscore:
        return '_';
      case QuickAction.comma:
        return ',';
      case QuickAction.dot:
        return '.';
      case QuickAction.undo:
        return 'Undo';
      case QuickAction.redo:
        return 'Redo';
    }
  }

  /// Text inserted at the cursor. Null for undo/redo, which are actions,
  /// not insertions.
  String? get insertText {
    switch (this) {
      case QuickAction.tab:
        return '  ';
      case QuickAction.undo:
      case QuickAction.redo:
        return null;
      default:
        return label;
    }
  }

  bool get isUndo => this == QuickAction.undo;
  bool get isRedo => this == QuickAction.redo;
}
