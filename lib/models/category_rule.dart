import 'package:cloud_firestore/cloud_firestore.dart';

enum RuleMatchType { contains, startsWith, equals, regex }

class CategoryRule {
  final String id;
  final String pattern;
  final RuleMatchType matchType;
  final String category;
  final int priority;
  final bool enabled;

  CategoryRule({
    required this.id,
    required this.pattern,
    required this.matchType,
    required this.category,
    required this.priority,
    required this.enabled,
  });

  static RuleMatchType matchTypeFromString(String s) {
    switch (s) {
      case 'startsWith':
        return RuleMatchType.startsWith;
      case 'equals':
        return RuleMatchType.equals;
      case 'regex':
        return RuleMatchType.regex;
      case 'contains':
      default:
        return RuleMatchType.contains;
    }
  }

  static String matchTypeToString(RuleMatchType t) {
    switch (t) {
      case RuleMatchType.startsWith:
        return 'startsWith';
      case RuleMatchType.equals:
        return 'equals';
      case RuleMatchType.regex:
        return 'regex';
      case RuleMatchType.contains:
        return 'contains';
    }
  }

  factory CategoryRule.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? {};
    return CategoryRule(
      id: doc.id,
      pattern: (data['pattern'] ?? '').toString(),
      matchType: matchTypeFromString(
        (data['matchType'] ?? 'contains').toString(),
      ),
      category: (data['category'] ?? 'Other').toString(),
      priority: (data['priority'] as num?)?.toInt() ?? 100,
      enabled: (data['enabled'] as bool?) ?? true,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'pattern': pattern,
      'matchType': matchTypeToString(matchType),
      'category': category,
      'priority': priority,
      'enabled': enabled,
      'updatedAt': FieldValue.serverTimestamp(),
    };
  }
}
