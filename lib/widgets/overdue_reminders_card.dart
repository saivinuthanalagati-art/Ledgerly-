import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../screens/settings_screen.dart'; // for ReminderNotifications.cancelForReminder (optional)

class OverdueRemindersCard extends StatelessWidget {
  const OverdueRemindersCard({super.key});

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return const SizedBox.shrink();
    final uid = user.uid;

    final now = DateTime.now();

    final q = FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('reminders')
        .where('dueDate', isLessThan: Timestamp.fromDate(now))
        .orderBy('dueDate', descending: true)
        .limit(30);

    String fmt(DateTime d) =>
        '${d.month.toString().padLeft(2, '0')}/${d.day.toString().padLeft(2, '0')}/${d.year}';

    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Text(
                  'Overdue',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
                ),
                const Spacer(),
                Text('Past due', style: TextStyle(color: Colors.grey.shade600)),
              ],
            ),
            const SizedBox(height: 10),
            StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: q.snapshots(),
              builder: (context, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return const LinearProgressIndicator();
                }

                final all = snap.data?.docs ?? [];

                final docs = all.where((d) {
                  final data = d.data();
                  final paid = (data['paid'] as bool?) ?? false;
                  final enabled = (data['enabled'] as bool?) ?? true;
                  return !paid && enabled;
                }).toList();

                if (docs.isEmpty) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 8),
                    child: Text('No overdue reminders 🎉'),
                  );
                }

                return Column(
                  children: docs.take(5).map((d) {
                    final data = d.data();
                    final title = (data['title'] ?? 'Reminder').toString();
                    final amount = (data['amount'] is num)
                        ? (data['amount'] as num).toDouble()
                        : null;

                    DateTime? due;
                    final ts = data['dueDate'];
                    if (ts is Timestamp) due = ts.toDate();

                    final subtitle = [
                      if (amount != null) '\$${amount.toStringAsFixed(2)}',
                      if (due != null) 'Due ${fmt(due)}',
                    ].join(' • ');

                    return ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.error_outline),
                      title: Text(
                        title,
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                      subtitle: subtitle.isEmpty ? null : Text(subtitle),
                      trailing: IconButton(
                        tooltip: 'Mark as paid',
                        icon: const Icon(Icons.check_circle_outline),
                        onPressed: () async {
                          await d.reference.set({
                            'paid': true,
                            'paidAt': FieldValue.serverTimestamp(),
                            'updatedAt': FieldValue.serverTimestamp(),
                            'enabled': true,
                          }, SetOptions(merge: true));
                          await ReminderNotifications.cancelForReminder(d.id);
                          if (!context.mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Marked as paid')),
                          );
                        },
                      ),
                    );
                  }).toList(),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
