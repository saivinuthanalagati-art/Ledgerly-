import '../models/category_rule.dart';

class RuleEngine {
  static bool _matches(CategoryRule r, String text) {
    final t = text.toLowerCase().trim();
    final p = r.pattern.toLowerCase().trim();
    if (p.isEmpty) return false;

    switch (r.matchType) {
      case RuleMatchType.contains:
        return t.contains(p);
      case RuleMatchType.startsWith:
        return t.startsWith(p);
      case RuleMatchType.equals:
        return t == p;
      case RuleMatchType.regex:
        try {
          return RegExp(r.pattern, caseSensitive: false).hasMatch(text);
        } catch (_) {
          return false;
        }
    }
  }
  static CategoryRule? suggestRule({
    required String note,
    required List<CategoryRule> rules,
  }) {
    final text = note.trim();
    if (text.isEmpty) return null;

    final enabledRules = rules.where((r) => r.enabled).toList()
      ..sort((a, b) => a.priority.compareTo(b.priority));

    for (final r in enabledRules) {
      if (_matches(r, text)) return r;
    }
    return null;
  }
  static String? suggestCategory({
    required String note,
    required List<CategoryRule> rules,
  }) {
    final text = note.trim();
    if (text.isEmpty) return null;

    final enabledRules = rules.where((r) => r.enabled).toList()
      ..sort((a, b) => a.priority.compareTo(b.priority));

    for (final r in enabledRules) {
      if (_matches(r, text)) return r.category;
    }
    return null;
  }
}
