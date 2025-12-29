import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'package:package_info_plus/package_info_plus.dart';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

import 'rules_screen.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  Future<void> _signOut(BuildContext context) async {
    await FirebaseAuth.instance.signOut();
    if (!context.mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Logged out')));
  }

  Future<void> _showAppInfo(BuildContext context) async {
    final info = await PackageInfo.fromPlatform();
    if (!context.mounted) return;

    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (_) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'App information',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 12),
            _kv('Name', info.appName),
            _kv('Package', info.packageName),
            _kv('Version', info.version),
            _kv('Build', info.buildNumber),
            const SizedBox(height: 10),
            const Text(
              'Budget AI • Flutter + Firebase',
              style: TextStyle(fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }

  Widget _kv(String k, String v) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          SizedBox(
            width: 90,
            child: Text(k, style: const TextStyle(fontWeight: FontWeight.w700)),
          ),
          Expanded(child: Text(v)),
        ],
      ),
    );
  }

  Future<void> _deleteAccountFlow(BuildContext context) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final email = user.email ?? '';

    final passwordCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete account'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'This will permanently delete your account and your data.',
            ),
            const SizedBox(height: 10),
            Text('Re-enter password for $email'),
            const SizedBox(height: 8),
            TextField(
              controller: passwordCtrl,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'Password'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (ok != true) {
      passwordCtrl.dispose();
      return;
    }

    final password = passwordCtrl.text;
    passwordCtrl.dispose();

    if (password.trim().isEmpty) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Password required')));
      return;
    }

    try {
      // Re-auth
      final cred = EmailAuthProvider.credential(
        email: email,
        password: password,
      );
      await user.reauthenticateWithCredential(cred);

      final uid = user.uid;
      await _deepDeleteUserData(uid);

      await user.delete();

      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Account deleted')));
    } on FirebaseAuthException catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message ?? 'Auth error: ${e.code}')),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Delete failed: $e')));
    }
  }

  Future<void> _deepDeleteUserData(String uid) async {
    final db = FirebaseFirestore.instance;
    final userDoc = db.collection('users').doc(uid);

    Future<void> deleteSubcollection(String name) async {
      while (true) {
        final q = await userDoc.collection(name).limit(300).get();
        if (q.docs.isEmpty) break;
        final batch = db.batch();
        for (final d in q.docs) {
          batch.delete(d.reference);
        }
        await batch.commit();
      }
    }

    await deleteSubcollection('reminders');

    await userDoc.delete();
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    final email = user?.email ?? 'Unknown';

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Account
          Card(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Account',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 10),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.person),
                    title: const Text('Signed in as'),
                    subtitle: Text(email),
                  ),
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerRight,
                    child: FilledButton.icon(
                      onPressed: () => _signOut(context),
                      icon: const Icon(Icons.logout),
                      label: const Text('Log out'),
                    ),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 12),

          Card(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.notifications_none),
                  title: const Text('Reminders'),
                  subtitle: const Text(
                    'Bills, subscriptions, goals (saved to Firestore)',
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const RemindersScreen(),
                      ),
                    );
                  },
                ),
                const Divider(height: 0),
                ListTile(
                  leading: const Icon(Icons.rule),
                  title: const Text('Auto-category rules'),
                  subtitle: const Text(
                    'Auto-assign categories based on note/merchant',
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const RulesScreen()),
                    );
                  },
                ),
                const Divider(height: 0),
                SwitchListTile(
                  secondary: const Icon(Icons.auto_awesome),
                  title: const Text('AI insights'),
                  subtitle: const Text('We’ll wire this setting up next'),
                  value: true,
                  onChanged: (_) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('We’ll wire this setting up next.'),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),

          const SizedBox(height: 12),

          // About
          Card(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.info_outline),
                  title: const Text('About'),
                  subtitle: const Text('Tap to view app information'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _showAppInfo(context),
                ),
                const Divider(height: 0),
                ListTile(
                  leading: const Icon(Icons.privacy_tip_outlined),
                  title: const Text('Privacy'),
                  subtitle: const Text(
                    'Your reminders are stored in your Firebase account.',
                  ),
                  onTap: () {
                    showDialog(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        title: const Text('Privacy'),
                        content: const Text(
                          'Budget AI stores reminders in Firestore under your user account.\n\n'
                          'Local notifications are used for reminder alerts.',
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(ctx),
                            child: const Text('OK'),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ],
            ),
          ),

          const SizedBox(height: 12),

          Card(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Danger zone',
                    style: Theme.of(
                      context,
                    ).textTheme.titleMedium?.copyWith(color: Colors.red),
                  ),
                  const SizedBox(height: 10),
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.red,
                      side: const BorderSide(color: Colors.red),
                    ),
                    onPressed: () => _deleteAccountFlow(context),
                    icon: const Icon(Icons.delete_forever),
                    label: const Text('Delete account'),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/* ===========================
   Notifications
   =========================== */

class ReminderNotifications {
  ReminderNotifications._();

  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  static bool _inited = false;

  static Future<void> init() async {
    if (_inited) return;

    tz.initializeTimeZones();

    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const initSettings = InitializationSettings(android: android);

    await _plugin.initialize(initSettings);

    const androidChannel = AndroidNotificationChannel(
      'reminders_channel',
      'Reminders',
      description: 'Reminder notifications',
      importance: Importance.high,
    );

    final androidPlugin = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    await androidPlugin?.createNotificationChannel(androidChannel);

    _inited = true;
  }

  static int _notifIdForDoc(String docId) {
    return docId.hashCode & 0x7fffffff;
  }

  static Future<void> scheduleForReminder({
    required String docId,
    required String title,
    String? body,
    required DateTime when,
  }) async {
    await init();

    final id = _notifIdForDoc(docId);
    final tzWhen = tz.TZDateTime.from(when, tz.local);

    if (tzWhen.isBefore(tz.TZDateTime.now(tz.local))) return;

    await _plugin.zonedSchedule(
      id,
      title,
      body ?? 'Payment due soon',
      tzWhen,
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'reminders_channel',
          'Reminders',
          importance: Importance.high,
          priority: Priority.high,
        ),
      ),
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
      matchDateTimeComponents: null,
    );
  }

  static Future<void> cancelForReminder(String docId) async {
    await init();
    await _plugin.cancel(_notifIdForDoc(docId));
  }
}

/* ===========================
   Reminders (Firestore CRUD)
   =========================== */

enum RepeatRule { none, weekly, monthly }

class RemindersScreen extends StatelessWidget {
  const RemindersScreen({super.key});

  CollectionReference<Map<String, dynamic>> _ref(String uid) {
    return FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('reminders');
  }

  String _repeatLabel(RepeatRule r) {
    switch (r) {
      case RepeatRule.none:
        return 'None';
      case RepeatRule.weekly:
        return 'Weekly';
      case RepeatRule.monthly:
        return 'Monthly';
    }
  }

  RepeatRule _repeatFromString(String? s) {
    switch (s) {
      case 'weekly':
        return RepeatRule.weekly;
      case 'monthly':
        return RepeatRule.monthly;
      case 'none':
      default:
        return RepeatRule.none;
    }
  }

  String _repeatToString(RepeatRule r) {
    switch (r) {
      case RepeatRule.weekly:
        return 'weekly';
      case RepeatRule.monthly:
        return 'monthly';
      case RepeatRule.none:
        return 'none';
    }
  }

  String _fmtDate(DateTime? d) {
    if (d == null) return 'No date';
    return '${d.month.toString().padLeft(2, '0')}/${d.day.toString().padLeft(2, '0')}/${d.year}';
  }

  Future<void> _syncNotificationForDoc({
    required String docId,
    required Map<String, dynamic> data,
  }) async {
    final enabled = (data['enabled'] as bool?) ?? true;
    final paid = (data['paid'] as bool?) ?? false;

    DateTime? due;
    final ts = data['dueDate'];
    if (ts is Timestamp) due = ts.toDate();

    if (!enabled || paid || due == null) {
      await ReminderNotifications.cancelForReminder(docId);
      return;
    }

    final title = (data['title'] ?? 'Reminder').toString();
    final amount = (data['amount'] is num)
        ? (data['amount'] as num).toDouble()
        : null;
    final body = amount == null
        ? 'Due ${_fmtDate(due)}'
        : '\$${amount.toStringAsFixed(2)} • Due ${_fmtDate(due)}';

    await ReminderNotifications.scheduleForReminder(
      docId: docId,
      title: title,
      body: body,
      when: due,
    );
  }

  Future<void> _openEditor(
    BuildContext context, {
    required String uid,
    String? docId,
    Map<String, dynamic>? existing,
  }) async {
    final titleCtrl = TextEditingController(
      text: (existing?['title'] ?? '').toString(),
    );
    final noteCtrl = TextEditingController(
      text: (existing?['note'] ?? '').toString(),
    );

    final num amt = (existing?['amount'] is num)
        ? existing!['amount'] as num
        : 0;
    final amountCtrl = TextEditingController(
      text: amt == 0 ? '' : amt.toString(),
    );

    final bool enabled = (existing?['enabled'] as bool?) ?? true;

    DateTime? dueDate;
    final ts = existing?['dueDate'];
    if (ts is Timestamp) dueDate = ts.toDate();

    RepeatRule repeat = _repeatFromString(
      (existing?['repeat'] ?? 'none').toString(),
    );

    bool tempEnabled = enabled;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            return Padding(
              padding: EdgeInsets.only(
                left: 16,
                right: 16,
                top: 10,
                bottom: MediaQuery.of(ctx).viewInsets.bottom + 18,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    docId == null ? 'New reminder' : 'Edit reminder',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 12),

                  TextField(
                    controller: titleCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Title (required)',
                      hintText: 'Rent, Netflix, Credit card payment…',
                    ),
                  ),
                  const SizedBox(height: 10),

                  TextField(
                    controller: amountCtrl,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: const InputDecoration(
                      labelText: 'Amount (optional)',
                      hintText: 'e.g. 29.99',
                    ),
                  ),
                  const SizedBox(height: 10),

                  TextField(
                    controller: noteCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Note (optional)',
                      hintText: 'Pay before due date, auto-pay, etc.',
                    ),
                  ),
                  const SizedBox(height: 12),

                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () async {
                            final picked = await showDatePicker(
                              context: ctx,
                              firstDate: DateTime(2020),
                              lastDate: DateTime(2100),
                              initialDate: dueDate ?? DateTime.now(),
                            );
                            if (picked != null) {
                              setSheetState(() => dueDate = picked);
                            }
                          },
                          icon: const Icon(Icons.event),
                          label: Text(
                            dueDate == null
                                ? 'Pick due date'
                                : _fmtDate(dueDate),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      if (dueDate != null)
                        IconButton(
                          tooltip: 'Clear date',
                          onPressed: () => setSheetState(() => dueDate = null),
                          icon: const Icon(Icons.clear),
                        ),
                    ],
                  ),

                  const SizedBox(height: 12),

                  Row(
                    children: [
                      const Icon(Icons.repeat),
                      const SizedBox(width: 10),
                      const Text('Repeat'),
                      const Spacer(),
                      DropdownButton<RepeatRule>(
                        value: repeat,
                        onChanged: (v) =>
                            setSheetState(() => repeat = v ?? RepeatRule.none),
                        items: RepeatRule.values
                            .map(
                              (r) => DropdownMenuItem(
                                value: r,
                                child: Text(_repeatLabel(r)),
                              ),
                            )
                            .toList(),
                      ),
                    ],
                  ),

                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Enabled'),
                    subtitle: const Text('Turn off without deleting'),
                    value: tempEnabled,
                    onChanged: (v) => setSheetState(() => tempEnabled = v),
                  ),

                  const SizedBox(height: 8),

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
                            final title = titleCtrl.text.trim();
                            if (title.isEmpty) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('Title is required'),
                                ),
                              );
                              return;
                            }

                            final amount = double.tryParse(
                              amountCtrl.text.trim(),
                            );
                            final payload = <String, dynamic>{
                              'title': title,
                              'note': noteCtrl.text.trim(),
                              'amount': amount,
                              'dueDate': dueDate == null
                                  ? null
                                  : Timestamp.fromDate(dueDate!),
                              'repeat': _repeatToString(repeat),
                              'enabled': tempEnabled,
                              'paid': (existing?['paid'] as bool?) ?? false,
                              'updatedAt': FieldValue.serverTimestamp(),
                              if (docId == null)
                                'createdAt': FieldValue.serverTimestamp(),
                            };

                            payload.removeWhere(
                              (k, v) =>
                                  v == null ||
                                  (v is String && v.trim().isEmpty),
                            );

                            final col = _ref(uid);
                            if (docId == null) {
                              final newDoc = await col.add(payload);
                              final fresh =
                                  (await newDoc.get()).data() ?? payload;
                              await _syncNotificationForDoc(
                                docId: newDoc.id,
                                data: fresh,
                              );
                            } else {
                              await col
                                  .doc(docId)
                                  .set(payload, SetOptions(merge: true));
                              final fresh =
                                  (await col.doc(docId).get()).data() ??
                                  payload;
                              await _syncNotificationForDoc(
                                docId: docId,
                                data: fresh,
                              );
                            }

                            if (context.mounted) {
                              Navigator.pop(ctx);
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Saved')),
                              );
                            }
                          },
                          child: const Text('Save'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        );
      },
    );

    titleCtrl.dispose();
    noteCtrl.dispose();
    amountCtrl.dispose();
  }

  Future<void> _deleteReminder(
    BuildContext context,
    String uid,
    String docId,
  ) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete reminder?'),
        content: const Text('This cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (ok == true) {
      await ReminderNotifications.cancelForReminder(docId);
      await _ref(uid).doc(docId).delete();
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Deleted')));
      }
    }
  }

  Future<void> _togglePaid({
    required BuildContext context,
    required String uid,
    required String docId,
    required bool currentPaid,
  }) async {
    final col = _ref(uid);
    final nextPaid = !currentPaid;

    await col.doc(docId).set({
      'paid': nextPaid,
      'paidAt': nextPaid ? FieldValue.serverTimestamp() : FieldValue.delete(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    final fresh = (await col.doc(docId).get()).data();
    if (fresh != null) {
      await _syncNotificationForDoc(docId: docId, data: fresh);
    }

    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(nextPaid ? 'Marked as paid' : 'Marked as unpaid')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser!;
    final uid = user.uid;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Reminders'),
        actions: [
          IconButton(
            tooltip: 'Add',
            onPressed: () => _openEditor(context, uid: uid),
            icon: const Icon(Icons.add),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openEditor(context, uid: uid),
        icon: const Icon(Icons.add),
        label: const Text('New'),
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: _ref(uid).orderBy('createdAt', descending: true).snapshots(),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          final docs = snap.data?.docs ?? [];

          if (docs.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'No reminders yet.\nTap “New” to add one.',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }

          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: docs.length,
            separatorBuilder: (_, _) => const SizedBox(height: 10),
            itemBuilder: (context, i) {
              final d = docs[i];
              final data = d.data();

              final title = (data['title'] ?? '').toString();
              final note = (data['note'] ?? '').toString();
              final enabled = (data['enabled'] as bool?) ?? true;
              final paid = (data['paid'] as bool?) ?? false;

              DateTime? due;
              final ts = data['dueDate'];
              if (ts is Timestamp) due = ts.toDate();

              final repeat = _repeatFromString(
                (data['repeat'] ?? 'none').toString(),
              );
              final amount = (data['amount'] is num)
                  ? (data['amount'] as num).toDouble()
                  : null;

              final subtitleParts = <String>[];
              if (amount != null) {
                subtitleParts.add('\$${amount.toStringAsFixed(2)}');
              }
              if (due != null) {
                subtitleParts.add('Due ${_fmtDate(due)}');
              }
              if (repeat != RepeatRule.none) {
                subtitleParts.add(_repeatLabel(repeat));
              }
              if (note.isNotEmpty) {
                subtitleParts.add(note);
              }

              final icon = paid
                  ? Icons.check_circle
                  : enabled
                  ? Icons.notifications_active
                  : Icons.notifications_off;

              return Card(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  children: [
                    ListTile(
                      leading: Icon(icon),
                      title: Text(
                        title,
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          decoration: paid ? TextDecoration.lineThrough : null,
                        ),
                      ),
                      subtitle: subtitleParts.isEmpty
                          ? const Text('No details')
                          : Text(
                              subtitleParts.join(' • '),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                      trailing: PopupMenuButton<String>(
                        onSelected: (v) async {
                          if (v == 'edit') {
                            await _openEditor(
                              context,
                              uid: uid,
                              docId: d.id,
                              existing: data,
                            );
                          } else if (v == 'toggle') {
                            await _ref(uid).doc(d.id).set({
                              'enabled': !enabled,
                            }, SetOptions(merge: true));
                            final fresh = (await _ref(
                              uid,
                            ).doc(d.id).get()).data();
                            if (fresh != null) {
                              await _syncNotificationForDoc(
                                docId: d.id,
                                data: fresh,
                              );
                            }
                          } else if (v == 'delete') {
                            await _deleteReminder(context, uid, d.id);
                          }
                        },
                        itemBuilder: (_) => [
                          const PopupMenuItem(
                            value: 'edit',
                            child: Text('Edit'),
                          ),
                          PopupMenuItem(
                            value: 'toggle',
                            child: Text(enabled ? 'Disable' : 'Enable'),
                          ),
                          const PopupMenuItem(
                            value: 'delete',
                            child: Text('Delete'),
                          ),
                        ],
                      ),
                      onTap: () => _openEditor(
                        context,
                        uid: uid,
                        docId: d.id,
                        existing: data,
                      ),
                    ),
                    const Divider(height: 0),
                    SwitchListTile(
                      secondary: const Icon(Icons.done_all),
                      title: const Text('Mark as paid'),
                      value: paid,
                      onChanged: (_) => _togglePaid(
                        context: context,
                        uid: uid,
                        docId: d.id,
                        currentPaid: paid,
                      ),
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }
}
