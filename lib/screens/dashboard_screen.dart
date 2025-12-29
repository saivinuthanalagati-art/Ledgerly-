import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../widgets/upcoming_reminders_card.dart';
import '../widgets/overdue_reminders_card.dart';
import '../models/category_rule.dart';
import '../services/rules_service.dart';
import '../services/rule_engine.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  Future<void> logout() => FirebaseAuth.instance.signOut();

  CollectionReference<Map<String, dynamic>> _txRef(String uid) {
    return FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('transactions');
  }

  DocumentReference<Map<String, dynamic>> _userRef(String uid) {
    return FirebaseFirestore.instance.collection('users').doc(uid);
  }

  String _fmtDate(DateTime d) =>
      '${d.month.toString().padLeft(2, '0')}/${d.day.toString().padLeft(2, '0')}/${d.year}';

  Future<void> _addTransactionDialog(String uid) async {
    final amountCtrl = TextEditingController();
    final noteCtrl = TextEditingController();
    String category = 'Food';
    String error = '';

    DateTime selectedDate = DateTime.now();

    await showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setLocal) {
            return AlertDialog(
              title: const Text('Add expense'),
              content: SizedBox(
                width: 420,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: amountCtrl,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: const InputDecoration(
                        labelText: 'Amount (e.g., 12.50)',
                      ),
                    ),
                    const SizedBox(height: 12),

                    OutlinedButton.icon(
                      icon: const Icon(Icons.event),
                      label: Text('Date: ${_fmtDate(selectedDate)}'),
                      onPressed: () async {
                        final picked = await showDatePicker(
                          context: ctx,
                          firstDate: DateTime(2020),
                          lastDate: DateTime(2100),
                          initialDate: selectedDate,
                        );
                        if (picked != null) {
                          setLocal(() => selectedDate = picked);
                        }
                      },
                    ),

                    const SizedBox(height: 12),

                    DropdownButtonFormField<String>(
                      key: ValueKey(category),
                      initialValue: category,
                      items: const [
                        DropdownMenuItem(value: 'Food', child: Text('Food')),
                        DropdownMenuItem(
                          value: 'Groceries',
                          child: Text('Groceries'),
                        ),
                        DropdownMenuItem(
                          value: 'Transport',
                          child: Text('Transport'),
                        ),
                        DropdownMenuItem(
                          value: 'Shopping',
                          child: Text('Shopping'),
                        ),
                        DropdownMenuItem(value: 'Bills', child: Text('Bills')),
                        DropdownMenuItem(value: 'Other', child: Text('Other')),
                      ],
                      onChanged: (v) => setLocal(() => category = v ?? 'Food'),
                      decoration: const InputDecoration(labelText: 'Category'),
                    ),
                    const SizedBox(height: 12),
                    StreamBuilder<List<CategoryRule>>(
                      stream: RulesService.streamRules(uid),
                      builder: (context, snap) {
                        final rules = snap.data ?? const <CategoryRule>[];

                        return TextField(
                          controller: noteCtrl,
                          decoration: const InputDecoration(
                            labelText: 'Note (optional)',
                          ),
                          onChanged: (txt) {
                            final suggestion = RuleEngine.suggestCategory(
                              note: txt,
                              rules: rules,
                            );
                            if (suggestion != null && suggestion != category) {
                              setLocal(() => category = suggestion);
                            }
                          },
                        );
                      },
                    ),

                    const SizedBox(height: 8),
                    if (error.isNotEmpty)
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          error,
                          style: const TextStyle(color: Colors.red),
                        ),
                      ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: () async {
                    final raw = amountCtrl.text.trim();
                    final amount = double.tryParse(raw);
                    if (amount == null || amount <= 0) {
                      setLocal(() => error = 'Enter a valid positive amount.');
                      return;
                    }

                    final when = DateTime(
                      selectedDate.year,
                      selectedDate.month,
                      selectedDate.day,
                      12,
                      0,
                    );

                    await _txRef(uid).add({
                      'amount': amount,
                      'category': category,
                      'note': noteCtrl.text.trim(),
                      'createdAt': Timestamp.fromDate(when),
                    });

                    if (ctx.mounted) Navigator.pop(ctx);
                  },
                  child: const Text('Add'),
                ),
              ],
            );
          },
        );
      },
    );

    amountCtrl.dispose();
    noteCtrl.dispose();
  }

  Future<void> _editBudgetDialog(String uid, double current) async {
    final ctrl = TextEditingController(text: current.toStringAsFixed(0));
    String error = '';

    await showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setLocal) {
            return AlertDialog(
              title: const Text('Set monthly budget'),
              content: SizedBox(
                width: 420,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: ctrl,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: const InputDecoration(
                        labelText: 'Budget amount',
                      ),
                    ),
                    const SizedBox(height: 8),
                    if (error.isNotEmpty)
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          error,
                          style: const TextStyle(color: Colors.red),
                        ),
                      ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: () async {
                    final value = double.tryParse(ctrl.text.trim());
                    if (value == null || value <= 0) {
                      setLocal(() => error = 'Enter a valid positive number.');
                      return;
                    }
                    await _userRef(
                      uid,
                    ).set({'monthlyBudget': value}, SetOptions(merge: true));
                    if (ctx.mounted) Navigator.pop(ctx);
                  },
                  child: const Text('Save'),
                ),
              ],
            );
          },
        );
      },
    );

    ctrl.dispose();
  }

  // ---------- Budget bar chart helpers ----------

  Map<String, double> _monthTotalsByCategory(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
    DateTime month,
  ) {
    final out = <String, double>{};

    for (final d in docs) {
      final data = d.data();
      final ts = data['createdAt'];
      if (ts is! Timestamp) continue;

      final dt = ts.toDate();
      if (dt.year != month.year || dt.month != month.month) continue;

      final cat = (data['category'] as String?) ?? 'Other';
      final amount = (data['amount'] as num?)?.toDouble() ?? 0.0;
      out[cat] = (out[cat] ?? 0) + amount;
    }

    return out;
  }

  List<String> _topCategories(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
    DateTime month, {
    int topN = 4,
  }) {
    final totals = _monthTotalsByCategory(docs, month);
    final entries = totals.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    final top = entries.take(topN).map((e) => e.key).toList();

    if (!top.contains('Other')) top.add('Other');
    return top;
  }

  List<Map<String, double>> _dailyCategoryTotalsForMonth(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
    DateTime month,
    List<String> cats,
  ) {
    final daysInMonth = DateTime(month.year, month.month + 1, 0).day;

    final out = List.generate(daysInMonth, (_) => <String, double>{});

    for (final d in docs) {
      final data = d.data();
      final ts = data['createdAt'];
      if (ts is! Timestamp) continue;

      final dt = ts.toDate();
      if (dt.year != month.year || dt.month != month.month) continue;

      final dayIndex = dt.day - 1;
      if (dayIndex < 0 || dayIndex >= out.length) continue;

      final rawCat = (data['category'] as String?) ?? 'Other';
      final amount = (data['amount'] as num?)?.toDouble() ?? 0.0;

      final cat = cats.contains(rawCat) ? rawCat : 'Other';
      out[dayIndex][cat] = (out[dayIndex][cat] ?? 0) + amount;
    }

    for (final m in out) {
      for (final c in cats) {
        m[c] = m[c] ?? 0.0;
      }
    }

    return out;
  }

  Color _catColor(BuildContext context, String cat, int i) {
    final base = Theme.of(context).colorScheme.primary;
    final opacities = [0.90, 0.70, 0.55, 0.40, 0.30, 0.22];
    final o = opacities[i % opacities.length];
    return base.withValues(alpha: o);
  }

  Widget _monthlyStackedCategoryChart(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
    DateTime month,
  ) {
    final cats = _topCategories(docs, month, topN: 4);
    final daily = _dailyCategoryTotalsForMonth(docs, month, cats);

    final totals = daily
        .map((m) => m.values.fold<double>(0.0, (a, b) => a + b))
        .toList();

    final maxTotal = totals.isEmpty
        ? 0.0
        : totals.reduce((a, b) => a > b ? a : b);
    final days = daily.length;

    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Spending this month (by category)',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 10),

            Wrap(
              spacing: 10,
              runSpacing: 8,
              children: [
                for (int i = 0; i < cats.length; i++)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 12,
                        height: 12,
                        decoration: BoxDecoration(
                          color: _catColor(context, cats[i], i),
                          borderRadius: BorderRadius.circular(3),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        cats[i],
                        style: TextStyle(color: Colors.grey.shade700),
                      ),
                    ],
                  ),
              ],
            ),

            const SizedBox(height: 12),

            SizedBox(
              height: 160,
              child: maxTotal <= 0
                  ? const Center(child: Text('No spending data yet.'))
                  : SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: List.generate(days, (dayIdx) {
                          const chartH = 110.0;
                          final dayMap = daily[dayIdx];
                          final dayTotal = totals[dayIdx];

                          final showLabel =
                              (dayIdx == 0) ||
                              ((dayIdx + 1) % 5 == 0) ||
                              (dayIdx == days - 1);

                          return Padding(
                            padding: const EdgeInsets.only(right: 6),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: [
                                Container(
                                  width: 12,
                                  height: chartH,
                                  decoration: BoxDecoration(
                                    color: Colors.grey.withValues(alpha: 0.10),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Align(
                                    alignment: Alignment.bottomCenter,
                                    child: Column(
                                      mainAxisAlignment: MainAxisAlignment.end,
                                      children: List.generate(cats.length, (i) {
                                        final cat = cats[i];
                                        final v = dayMap[cat] ?? 0.0;

                                        final segH = (v / maxTotal) * chartH;
                                        if (segH <= 0.5) {
                                          return const SizedBox.shrink();
                                        }

                                        return Container(
                                          width: 12,
                                          height: segH,
                                          decoration: BoxDecoration(
                                            color: _catColor(context, cat, i),
                                            borderRadius: BorderRadius.circular(
                                              8,
                                            ),
                                          ),
                                        );
                                      }),
                                    ),
                                  ),
                                ),

                                const SizedBox(height: 6),

                                SizedBox(
                                  width: 16,
                                  child: Text(
                                    showLabel ? '${dayIdx + 1}' : '',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      fontSize: 10,
                                      color: Colors.grey.shade600,
                                    ),
                                  ),
                                ),

                                if (dayTotal > 0 && dayTotal == maxTotal)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 2),
                                    child: Text(
                                      '★',
                                      style: TextStyle(
                                        fontSize: 10,
                                        color: Colors.grey.shade700,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          );
                        }),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser!;
    final uid = user.uid;

    final now = DateTime.now();
    final startOfMonth = DateTime(now.year, now.month, 1);

    final txStream = _txRef(uid)
        .where(
          'createdAt',
          isGreaterThanOrEqualTo: Timestamp.fromDate(startOfMonth),
        )
        .orderBy('createdAt', descending: true)
        .snapshots();

    return Scaffold(
      appBar: AppBar(
        title: const Text("Budget AI"),
        actions: [
          IconButton(onPressed: logout, icon: const Icon(Icons.logout)),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _addTransactionDialog(uid),
        child: const Icon(Icons.add),
      ),
      body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: _userRef(uid).snapshots(),
        builder: (context, userSnap) {
          final data = userSnap.data?.data();
          final monthlyBudget =
              (data?['monthlyBudget'] as num?)?.toDouble() ?? 500.0;

          return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: txStream,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snapshot.hasError) {
                return Center(child: Text('Error: ${snapshot.error}'));
              }

              final docs = snapshot.data?.docs ?? [];

              double total = 0;
              for (final d in docs) {
                total += (d.data()['amount'] as num?)?.toDouble() ?? 0;
              }

              final over = total > monthlyBudget;
              final progress = monthlyBudget <= 0
                  ? 0.0
                  : (total / monthlyBudget).clamp(0.0, 1.0);

              return ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  // Budget banner and progress bar
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      color: over
                          ? Colors.red.withValues(alpha: 0.10)
                          : Colors.indigo.withValues(alpha: 0.08),
                      border: Border.all(
                        color: over
                            ? Colors.red.withValues(alpha: 0.4)
                            : Colors.indigo.withValues(alpha: 0.25),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                'This month: \$${total.toStringAsFixed(2)} / \$${monthlyBudget.toStringAsFixed(0)}',
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            TextButton(
                              onPressed: () =>
                                  _editBudgetDialog(uid, monthlyBudget),
                              child: const Text('Edit'),
                            ),
                            if (over)
                              const Text(
                                'Over budget!',
                                style: TextStyle(
                                  color: Colors.red,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(99),
                          child: LinearProgressIndicator(
                            value: progress,
                            minHeight: 10,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          '${(progress * 100).toStringAsFixed(0)}% of budget used',
                          style: TextStyle(
                            color: Colors.grey.shade700,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 12),

                  // Monthly bar chart
                  _monthlyStackedCategoryChart(docs, now),

                  const SizedBox(height: 12),

                  // Overdue + Upcoming reminders
                  const OverdueRemindersCard(),
                  const SizedBox(height: 12),
                  const UpcomingRemindersCard(),

                  const SizedBox(height: 12),

                  // Transactions list
                  Card(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Transactions',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          const SizedBox(height: 10),
                          if (docs.isEmpty)
                            const Padding(
                              padding: EdgeInsets.symmetric(vertical: 10),
                              child: Text(
                                'No transactions yet. Tap + to add one.',
                              ),
                            )
                          else
                            ListView.separated(
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              itemCount: docs.length,
                              separatorBuilder: (_, _) =>
                                  const Divider(height: 1),
                              itemBuilder: (context, i) {
                                final data = docs[i].data();
                                final amount =
                                    ((data['amount'] as num?)?.toDouble() ?? 0);
                                final category =
                                    (data['category'] as String?) ?? 'Other';
                                final note = (data['note'] as String?) ?? '';

                                DateTime? when;
                                final ts = data['createdAt'];
                                if (ts is Timestamp) when = ts.toDate();

                                return ListTile(
                                  leading: CircleAvatar(
                                    child: Text(category.characters.first),
                                  ),
                                  title: Text(
                                    '$category • \$${amount.toStringAsFixed(2)}',
                                  ),
                                  subtitle: Text(
                                    [
                                      if (when != null) _fmtDate(when),
                                      if (note.isNotEmpty) note,
                                    ].join(' • '),
                                  ),
                                );
                              },
                            ),
                        ],
                      ),
                    ),
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }
}
