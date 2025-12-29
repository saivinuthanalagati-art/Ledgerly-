import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../models/category_rule.dart';
import '../services/rules_service.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../services/transactions_service.dart';
import '../services/rule_engine.dart';

class RulesScreen extends StatelessWidget {
  const RulesScreen({super.key});

  static const categories = <String>[
    'Food',
    'Groceries',
    'Transport',
    'Shopping',
    'Bills',
    'Other',
  ];

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser!;
    final uid = user.uid;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Auto-category rules'),
        actions: [
          IconButton(
            tooltip: 'Apply rules',
            icon: const Icon(Icons.auto_fix_high),
            onPressed: () async {
              final rulesSnap = await RulesService.rulesRef(
                uid,
              ).orderBy('priority').get();
              final rules = rulesSnap.docs
                  .map((d) => CategoryRule.fromDoc(d))
                  .toList();

              if (!context.mounted) return;
              await _applyRulesToExistingTransactions(context, uid, rules);
            },
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _openEditor(context, uid: uid),
        child: const Icon(Icons.add),
      ),
      body: StreamBuilder<List<CategoryRule>>(
        stream: RulesService.streamRules(uid),
        builder: (context, snap) {
          final rules = snap.data ?? [];
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (rules.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text('No rules yet.\nTap + to add one.'),
              ),
            );
          }

          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: rules.length,
            separatorBuilder: (_, _) => const SizedBox(height: 10),
            itemBuilder: (context, i) {
              final r = rules[i];
              return Card(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                child: ListTile(
                  title: Text(
                    '${r.category}  •  ${CategoryRule.matchTypeToString(r.matchType)} "${r.pattern}"',
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  subtitle: Text(
                    'Priority: ${r.priority}${r.enabled ? '' : ' • Disabled'}',
                  ),
                  trailing: PopupMenuButton<String>(
                    onSelected: (v) async {
                      if (v == 'edit') {
                        await _openEditor(context, uid: uid, existing: r);
                      } else if (v == 'toggle') {
                        await RulesService.upsertRule(
                          uid,
                          id: r.id,
                          rule: CategoryRule(
                            id: r.id,
                            pattern: r.pattern,
                            matchType: r.matchType,
                            category: r.category,
                            priority: r.priority,
                            enabled: !r.enabled,
                          ),
                        );
                      } else if (v == 'delete') {
                        await RulesService.deleteRule(uid, r.id);
                      }
                    },
                    itemBuilder: (_) => [
                      const PopupMenuItem(value: 'edit', child: Text('Edit')),
                      PopupMenuItem(
                        value: 'toggle',
                        child: Text(r.enabled ? 'Disable' : 'Enable'),
                      ),
                      const PopupMenuItem(
                        value: 'delete',
                        child: Text('Delete'),
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }

  Future<void> _openEditor(
    BuildContext context, {
    required String uid,
    CategoryRule? existing,
  }) async {
    final patternCtrl = TextEditingController(text: existing?.pattern ?? '');
    RuleMatchType matchType = existing?.matchType ?? RuleMatchType.contains;
    String category = existing?.category ?? 'Food';
    final priorityCtrl = TextEditingController(
      text: (existing?.priority ?? 100).toString(),
    );
    bool enabled = existing?.enabled ?? true;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => Padding(
          padding: EdgeInsets.only(
            left: 16,
            right: 16,
            top: 10,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 18,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                existing == null ? 'New rule' : 'Edit rule',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: patternCtrl,
                decoration: const InputDecoration(
                  labelText: 'Pattern',
                  hintText: 'uber, walmart, netflix…',
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  const Text('Match'),
                  const Spacer(),
                  DropdownButton<RuleMatchType>(
                    value: matchType,
                    onChanged: (v) =>
                        setS(() => matchType = v ?? RuleMatchType.contains),
                    items: RuleMatchType.values
                        .map(
                          (t) => DropdownMenuItem(
                            value: t,
                            child: Text(CategoryRule.matchTypeToString(t)),
                          ),
                        )
                        .toList(),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  const Text('Category'),
                  const Spacer(),
                  DropdownButton<String>(
                    value: category,
                    onChanged: (v) => setS(() => category = v ?? 'Food'),
                    items: categories
                        .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                        .toList(),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              TextField(
                controller: priorityCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Priority (lower runs first)',
                  hintText: 'e.g. 10',
                ),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Enabled'),
                value: enabled,
                onChanged: (v) => setS(() => enabled = v),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: const Text('Cancel'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      onPressed: () async {
                        final p = patternCtrl.text.trim();
                        if (p.isEmpty) return;

                        final pr =
                            int.tryParse(priorityCtrl.text.trim()) ?? 100;

                        final rule = CategoryRule(
                          id: existing?.id ?? '',
                          pattern: p,
                          matchType: matchType,
                          category: category,
                          priority: pr,
                          enabled: enabled,
                        );

                        await RulesService.upsertRule(
                          uid,
                          id: existing?.id,
                          rule: rule,
                        );

                        if (ctx.mounted) Navigator.pop(ctx);
                      },
                      child: const Text('Save'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );

    patternCtrl.dispose();
    priorityCtrl.dispose();
  }

  Future<void> _applyRulesToExistingTransactions(
    BuildContext context,
    String uid,
    List<CategoryRule> rules,
  ) async {
    if (rules.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('No rules found to apply.')));
      return;
    }

    bool onlyOther = true;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          title: const Text('Apply rules to existing transactions'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'This will scan your past transactions and auto-assign categories based on rules.',
              ),
              const SizedBox(height: 12),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Only update uncategorized / Other'),
                subtitle: const Text(
                  'Recommended (prevents overwriting your choices)',
                ),
                value: onlyOther,
                onChanged: (v) => setS(() => onlyOther = v ?? true),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Apply'),
            ),
          ],
        ),
      ),
    );

    if (ok != true) return;
    if (!context.mounted) return;
    // Progress UI
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const AlertDialog(
        content: SizedBox(
          height: 70,
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 12),
                Text('Applying rules…'),
              ],
            ),
          ),
        ),
      ),
    );

    int updated = 0;

    try {
      final col = TransactionsService.txRef(uid);

      Query<Map<String, dynamic>> query = col
          .orderBy('createdAt', descending: true)
          .limit(300);

      DocumentSnapshot<Map<String, dynamic>>? last;

      while (true) {
        final page = await (last == null
            ? query.get()
            : query.startAfterDocument(last).get());
        final docs = page.docs;
        if (docs.isEmpty) break;

        final batch = FirebaseFirestore.instance.batch();

        for (final d in docs) {
          final data = d.data();

          final note = (data['note'] ?? '').toString();
          if (note.trim().isEmpty) continue;

          final currentCategory = (data['category'] ?? '').toString().trim();

          if (onlyOther) {
            if (currentCategory.isNotEmpty &&
                currentCategory.toLowerCase() != 'other') {
              continue;
            }
          }

          final rule = RuleEngine.suggestRule(note: note, rules: rules);
          if (rule == null) continue;

          if (rule.category == currentCategory) continue;

          batch.set(d.reference, {
            'category': rule.category,
            'autoCategorized': true,
            'autoRuleId': rule.id,
            'updatedAt': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));
          updated++;
        }

        await batch.commit();
        last = docs.last;
      }

      if (context.mounted) Navigator.pop(context);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Applied rules. Updated $updated transaction(s).'),
        ),
      );
    } catch (e) {
      if (context.mounted) Navigator.pop(context);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Apply failed: $e')));
    }
  }
}
