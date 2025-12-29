import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class InsightsScreen extends StatelessWidget {
  const InsightsScreen({super.key});

  DocumentReference<Map<String, dynamic>> _userRef(String uid) {
    return FirebaseFirestore.instance.collection('users').doc(uid);
  }

  CollectionReference<Map<String, dynamic>> _txRef(String uid) {
    return FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('transactions');
  }

  DateTime _startOfMonth(DateTime now) => DateTime(now.year, now.month, 1);

  int _daysInMonth(DateTime now) {
    final firstNextMonth = DateTime(now.year, now.month + 1, 1);
    return firstNextMonth.subtract(const Duration(days: 1)).day;
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser!;
    final uid = user.uid;

    final now = DateTime.now();
    final start = _startOfMonth(now);
    final dayOfMonth = now.day;
    final daysInMonth = _daysInMonth(now);

    final txStream = _txRef(uid)
        .where('createdAt', isGreaterThanOrEqualTo: Timestamp.fromDate(start))
        .orderBy('createdAt', descending: true)
        .snapshots();

    return Scaffold(
      appBar: AppBar(title: const Text('Insights')),
      body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: _userRef(uid).snapshots(),
        builder: (context, userSnap) {
          final userData = userSnap.data?.data();
          final budget =
              (userData?['monthlyBudget'] as num?)?.toDouble() ?? 500.0;

          return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: txStream,
            builder: (context, snap) {
              if (snap.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snap.hasError) {
                return Center(child: Text('Error: ${snap.error}'));
              }

              final docs = snap.data?.docs ?? [];

              // Compute totals + category breakdown
              double total = 0;
              final categoryTotals = <String, double>{};
              double biggest = 0;
              String biggestCat = 'Other';

              for (final d in docs) {
                final data = d.data();
                final amount = (data['amount'] as num?)?.toDouble() ?? 0;
                final cat = (data['category'] as String?) ?? 'Other';

                total += amount;
                categoryTotals[cat] = (categoryTotals[cat] ?? 0) + amount;

                if (amount > biggest) {
                  biggest = amount;
                  biggestCat = cat;
                }
              }

              // Top category
              String topCat = 'None';
              double topCatAmount = 0;
              categoryTotals.forEach((k, v) {
                if (v > topCatAmount) {
                  topCatAmount = v;
                  topCat = k;
                }
              });
              final topCatPct =
                  total > 0 ? ((topCatAmount / total) * 100) : 0.0;

              // Burn rate + forecast
              final daysSoFar = dayOfMonth.clamp(1, 31);
              final dailyAvg = total / daysSoFar;
              final forecast = dailyAvg * daysInMonth;

              // Budget status
              final pctUsed = budget > 0 ? (total / budget) : 0.0;
              final isOver = total > budget;
              final isClose = !isOver && pctUsed >= 0.80;

              // Build “AI messages”
              final messages = <_InsightCardData>[
                _InsightCardData(
                  title: 'Budget status',
                  body: isOver
                      ? 'You are over budget by \$${(total - budget).toStringAsFixed(2)}. Consider pausing non-essential spending for a few days.'
                      : isClose
                          ? 'You’ve used ${(pctUsed * 100).toStringAsFixed(0)}% of your budget. You’re close — keep the next few days lighter.'
                          : 'You’ve used ${(pctUsed * 100).toStringAsFixed(0)}% of your budget. You’re on track.',
                  tone: isOver
                      ? _Tone.danger
                      : isClose
                          ? _Tone.warn
                          : _Tone.good,
                ),
                _InsightCardData(
                  title: 'Daily pace',
                  body:
                      'You’re averaging \$${dailyAvg.toStringAsFixed(2)} per day this month. To stay within \$${budget.toStringAsFixed(0)}, aim for about \$${(budget / daysInMonth).toStringAsFixed(2)}/day.',
                  tone: _Tone.neutral,
                ),
                _InsightCardData(
                  title: 'Top spending category',
                  body: docs.isEmpty
                      ? 'Add a few transactions and I’ll detect your top category.'
                      : '$topCat is your biggest category: \$${topCatAmount.toStringAsFixed(2)} (${topCatPct.toStringAsFixed(0)}% of total). Try setting a weekly cap for $topCat.',
                  tone: _Tone.neutral,
                ),
                _InsightCardData(
                  title: 'Forecast',
                  body: docs.isEmpty
                      ? 'Once you add transactions, I can forecast your end-of-month spend.'
                      : 'If you keep this pace, you’ll end the month around \$${forecast.toStringAsFixed(0)}. That’s ${forecast > budget ? 'above' : 'within'} your \$${budget.toStringAsFixed(0)} budget.',
                  tone: forecast > budget ? _Tone.warn : _Tone.good,
                ),
                _InsightCardData(
                  title: 'Biggest expense',
                  body: docs.isEmpty
                      ? 'No expenses yet.'
                      : 'Your biggest single expense was \$${biggest.toStringAsFixed(2)} in $biggestCat. If that’s recurring, consider budgeting for it explicitly.',
                  tone: _Tone.neutral,
                ),
              ];

              return ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Text(
                    'AI Insights',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Based on your spending this month.',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 16),
                  ...messages.map((m) => _InsightCard(m)),
                  const SizedBox(height: 24),
                ],
              );
            },
          );
        },
      ),
    );
  }
}

enum _Tone { good, warn, danger, neutral }

class _InsightCardData {
  final String title;
  final String body;
  final _Tone tone;

  _InsightCardData({
    required this.title,
    required this.body,
    required this.tone,
  });
}

class _InsightCard extends StatelessWidget {
  final _InsightCardData data;
  const _InsightCard(this.data);

  @override
  Widget build(BuildContext context) {
    Color border;
    Color bg;

    switch (data.tone) {
      case _Tone.good:
        border = Colors.green.withValues(alpha:0.35);
        bg = Colors.green.withValues(alpha:0.08);
        break;
      case _Tone.warn:
        border = Colors.orange.withValues(alpha:0.45);
        bg = Colors.orange.withValues(alpha:0.10);
        break;
      case _Tone.danger:
        border = Colors.red.withValues(alpha:0.45);
        bg = Colors.red.withValues(alpha:0.10);
        break;
      case _Tone.neutral:
        border = Colors.indigo.withValues(alpha:0.25);
        bg = Colors.indigo.withValues(alpha:0.06);
        break;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: border),
        color: bg,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(data.title,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          Text(data.body, style: const TextStyle(fontSize: 14)),
        ],
      ),
    );
  }
}
