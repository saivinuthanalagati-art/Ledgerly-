import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/category_rule.dart';

class RulesService {
  static CollectionReference<Map<String, dynamic>> rulesRef(String uid) {
    return FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('rules');
  }

  static Stream<List<CategoryRule>> streamRules(String uid) {
    return rulesRef(uid).orderBy('priority').snapshots().map((snap) {
      return snap.docs.map((d) => CategoryRule.fromDoc(d)).toList();
    });
  }

  static Future<void> upsertRule(
    String uid, {
    String? id,
    required CategoryRule rule,
  }) async {
    final ref = rulesRef(uid);
    if (id == null) {
      await ref.add({
        ...rule.toMap(),
        'createdAt': FieldValue.serverTimestamp(),
      });
    } else {
      await ref.doc(id).set(rule.toMap(), SetOptions(merge: true));
    }
  }

  static Future<void> deleteRule(String uid, String id) async {
    await rulesRef(uid).doc(id).delete();
  }
}
