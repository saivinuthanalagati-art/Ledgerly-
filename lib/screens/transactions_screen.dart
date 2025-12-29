import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class TransactionsScreen extends StatefulWidget {
  const TransactionsScreen({super.key});

  @override
  State<TransactionsScreen> createState() => _TransactionsScreenState();
}

enum DatePreset { allTime, thisMonth, last7Days, today, custom }

enum SortField { date, amount }

class _TransactionsScreenState extends State<TransactionsScreen> {
  CollectionReference<Map<String, dynamic>> _txRef(String uid) {
    return FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('transactions');
  }

  // Filters/UI state
  final TextEditingController searchCtrl = TextEditingController();

  String categoryFilter = 'All';

  DatePreset datePreset = DatePreset.thisMonth;
  DateTime? customStart;
  DateTime? customEnd;

  SortField sortField = SortField.date;
  bool sortDesc = true;

  // Bulk delete selection
  bool selectionMode = false;
  final Set<String> selectedIds = {};

  @override
  void dispose() {
    searchCtrl.dispose();
    super.dispose();
  }

  DateTime _startOfMonth(DateTime now) => DateTime(now.year, now.month, 1);

  DateTime _startOfDay(DateTime dt) => DateTime(dt.year, dt.month, dt.day);

  String _fmtTimestamp(Timestamp? ts) {
    if (ts == null) return '…';
    final dt = ts.toDate();
    final two = (int n) => n.toString().padLeft(2, '0');
    return '${dt.year}-${two(dt.month)}-${two(dt.day)} ${two(dt.hour)}:${two(dt.minute)}';
  }

  String _fmtDate(DateTime d) {
    final two = (int n) => n.toString().padLeft(2, '0');
    return '${d.year}-${two(d.month)}-${two(d.day)}';
  }

  DateTime? _computedStart(DateTime now) {
    switch (datePreset) {
      case DatePreset.allTime:
        return null;
      case DatePreset.thisMonth:
        return _startOfMonth(now);
      case DatePreset.last7Days:
        return now.subtract(const Duration(days: 7));
      case DatePreset.today:
        return _startOfDay(now);
      case DatePreset.custom:
        return customStart;
    }
  }

  DateTime? _computedEndExclusive(DateTime now) {
    if (datePreset != DatePreset.custom) return null;
    if (customEnd == null) return null;
    final e = _startOfDay(customEnd!);
    return e.add(const Duration(days: 1));
  }

  Future<void> _pickCustomRange() async {
    final now = DateTime.now();
    final initialStart = customStart ?? _startOfMonth(now);
    final initialEnd = customEnd ?? now;

    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 5, 1, 1),
      lastDate: DateTime(now.year + 1, 12, 31),
      initialDateRange: DateTimeRange(start: initialStart, end: initialEnd),
    );

    if (picked == null) return;

    setState(() {
      customStart = _startOfDay(picked.start);
      customEnd = _startOfDay(picked.end);
      datePreset = DatePreset.custom;
    });
  }

  Future<void> _deleteWithUndo({
    required String uid,
    required QueryDocumentSnapshot<Map<String, dynamic>> doc,
  }) async {
    final docId = doc.id;
    final data = doc.data();

    final amount = ((data['amount'] as num?)?.toDouble() ?? 0);
    final category = (data['category'] as String?) ?? 'Other';

    await _txRef(uid).doc(docId).delete();
    if (!mounted) return;

    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          content: Text('Deleted $category • \$${amount.toStringAsFixed(2)}'),
          action: SnackBarAction(
            label: 'Undo',
            onPressed: () async {
              await _txRef(uid).doc(docId).set(data);
            },
          ),
          duration: const Duration(seconds: 5),
        ),
      );
  }

  Future<void> _bulkDelete(String uid) async {
    if (selectedIds.isEmpty) return;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete selected transactions?'),
        content: Text('This will delete ${selectedIds.length} transaction(s).'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (ok != true) return;

    final batch = FirebaseFirestore.instance.batch();
    for (final id in selectedIds) {
      batch.delete(_txRef(uid).doc(id));
    }
    await batch.commit();

    if (!mounted) return;
    setState(() {
      selectionMode = false;
      selectedIds.clear();
    });

    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(
        const SnackBar(content: Text('Deleted selected transactions')),
      );
  }

  Query<Map<String, dynamic>> _buildBaseQuery({
    required String uid,
    required DateTime now,
  }) {
    Query<Map<String, dynamic>> q = _txRef(uid);

    final start = _computedStart(now);
    final endExclusive = _computedEndExclusive(now);

    if (start != null) {
      q = q.where(
        'createdAt',
        isGreaterThanOrEqualTo: Timestamp.fromDate(start),
      );
    }
    if (endExclusive != null) {
      q = q.where('createdAt', isLessThan: Timestamp.fromDate(endExclusive));
    }

    q = q.orderBy('createdAt', descending: true);

    return q;
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser!;
    final uid = user.uid;
    final now = DateTime.now();

    final txStream = _buildBaseQuery(uid: uid, now: now).snapshots();

    const categoryOptions = [
      'All',
      'Food',
      'Groceries',
      'Transport',
      'Shopping',
      'Bills',
      'Other',
    ];

    final normalizedSearch = searchCtrl.text.trim().toLowerCase();

    return Scaffold(
      appBar: AppBar(
        title: selectionMode
            ? Text('Selected: ${selectedIds.length}')
            : const Text('Transactions'),
        actions: [
          if (selectionMode) ...[
            IconButton(
              tooltip: 'Delete selected',
              onPressed: selectedIds.isEmpty ? null : () => _bulkDelete(uid),
              icon: const Icon(Icons.delete),
            ),
            IconButton(
              tooltip: 'Cancel selection',
              onPressed: () => setState(() {
                selectionMode = false;
                selectedIds.clear();
              }),
              icon: const Icon(Icons.close),
            ),
          ],
        ],
      ),
      body: Column(
        children: [
          // Filters
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        key: ValueKey(categoryFilter),
                        initialValue: categoryFilter,
                        items: categoryOptions
                            .map(
                              (c) => DropdownMenuItem(value: c, child: Text(c)),
                            )
                            .toList(),
                        onChanged: (v) =>
                            setState(() => categoryFilter = v ?? 'All'),
                        decoration: const InputDecoration(
                          labelText: 'Category',
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextField(
                        controller: searchCtrl,
                        decoration: InputDecoration(
                          labelText: 'Search note/category',
                          suffixIcon: searchCtrl.text.isEmpty
                              ? null
                              : IconButton(
                                  icon: const Icon(Icons.clear),
                                  onPressed: () =>
                                      setState(() => searchCtrl.clear()),
                                ),
                        ),
                        onChanged: (_) => setState(() {}),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    // Date preset
                    Expanded(
                      child: DropdownButtonFormField<DatePreset>(
                        key: ValueKey(datePreset),
                        initialValue: datePreset,
                        items: const [
                          DropdownMenuItem(
                            value: DatePreset.thisMonth,
                            child: Text('This month'),
                          ),
                          DropdownMenuItem(
                            value: DatePreset.last7Days,
                            child: Text('Last 7 days'),
                          ),
                          DropdownMenuItem(
                            value: DatePreset.today,
                            child: Text('Today'),
                          ),
                          DropdownMenuItem(
                            value: DatePreset.allTime,
                            child: Text('All time'),
                          ),
                          DropdownMenuItem(
                            value: DatePreset.custom,
                            child: Text('Custom'),
                          ),
                        ],
                        onChanged: (v) async {
                          if (v == null) return;
                          if (v == DatePreset.custom) {
                            await _pickCustomRange();
                          } else {
                            setState(() {
                              datePreset = v;
                            });
                          }
                        },
                        decoration: const InputDecoration(
                          labelText: 'Date range',
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    // Sort
                    Expanded(
                      child: DropdownButtonFormField<SortField>(
                        key: ValueKey(sortField),
                        initialValue: sortField,
                        items: const [
                          DropdownMenuItem(
                            value: SortField.date,
                            child: Text('Sort: Date'),
                          ),
                          DropdownMenuItem(
                            value: SortField.amount,
                            child: Text('Sort: Amount'),
                          ),
                        ],
                        onChanged: (v) =>
                            setState(() => sortField = v ?? SortField.date),
                        decoration: const InputDecoration(
                          labelText: 'Sort field',
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    IconButton(
                      tooltip: sortDesc ? 'Descending' : 'Ascending',
                      onPressed: () => setState(() => sortDesc = !sortDesc),
                      icon: Icon(sortDesc ? Icons.south : Icons.north),
                    ),
                  ],
                ),
                if (datePreset == DatePreset.custom &&
                    customStart != null &&
                    customEnd != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'Custom: ${_fmtDate(customStart!)} → ${_fmtDate(customEnd!)}',
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
                  ),
              ],
            ),
          ),

          const Divider(height: 1),

          // Data
          Expanded(
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: txStream,
              builder: (context, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snap.hasError) {
                  return Center(child: Text('Error: ${snap.error}'));
                }

                final docs = snap.data?.docs ?? [];

                // Client-side filter + sort
                final filtered = docs.where((d) {
                  final data = d.data();
                  final cat = (data['category'] as String?) ?? 'Other';
                  final note = (data['note'] as String?) ?? '';

                  final matchesCategory =
                      (categoryFilter == 'All') || (cat == categoryFilter);

                  final haystack = '${note.toLowerCase()} ${cat.toLowerCase()}';
                  final matchesSearch =
                      normalizedSearch.isEmpty ||
                      haystack.contains(normalizedSearch);

                  return matchesCategory && matchesSearch;
                }).toList();

                filtered.sort((a, b) {
                  final da = a.data();
                  final db = b.data();

                  int cmp;
                  if (sortField == SortField.amount) {
                    final aa = ((da['amount'] as num?)?.toDouble() ?? 0);
                    final bb = ((db['amount'] as num?)?.toDouble() ?? 0);
                    cmp = aa.compareTo(bb);
                  } else {
                    final ta = (da['createdAt'] as Timestamp?)?.toDate();
                    final tb = (db['createdAt'] as Timestamp?)?.toDate();
                    if (ta == null && tb == null) {
                      cmp = 0;
                    } else if (ta == null) {
                      cmp = -1;
                    } else if (tb == null) {
                      cmp = 1;
                    } else {
                      cmp = ta.compareTo(tb);
                    }
                  }
                  return sortDesc ? -cmp : cmp;
                });

                double total = 0;
                for (final d in filtered) {
                  total += ((d.data()['amount'] as num?)?.toDouble() ?? 0);
                }

                return Column(
                  children: [
                    // Summary row
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              '${filtered.length} transaction(s) • Total: \$${total.toStringAsFixed(2)}',
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          TextButton.icon(
                            onPressed: filtered.isEmpty
                                ? null
                                : () => setState(() {
                                    selectionMode = true;
                                    selectedIds.clear();
                                  }),
                            icon: const Icon(Icons.select_all, size: 18),
                            label: const Text('Select'),
                          ),
                        ],
                      ),
                    ),

                    const Divider(height: 1),

                    // List
                    Expanded(
                      child: filtered.isEmpty
                          ? const Center(
                              child: Text(
                                'No matching transactions.\nTry changing filters.',
                                textAlign: TextAlign.center,
                              ),
                            )
                          : ListView.separated(
                              itemCount: filtered.length,
                              separatorBuilder: (_, _) =>
                                  const Divider(height: 1),
                              itemBuilder: (context, i) {
                                final doc = filtered[i];
                                final data = doc.data();

                                final docId = doc.id;
                                final amount =
                                    ((data['amount'] as num?)?.toDouble() ?? 0);
                                final category =
                                    (data['category'] as String?) ?? 'Other';
                                final note = (data['note'] as String?) ?? '';
                                final createdAt =
                                    data['createdAt'] as Timestamp?;

                                final isSelected = selectedIds.contains(docId);

                                return ListTile(
                                  onLongPress: () {
                                    setState(() {
                                      selectionMode = true;
                                      if (isSelected) {
                                        selectedIds.remove(docId);
                                      } else {
                                        selectedIds.add(docId);
                                      }
                                    });
                                  },
                                  onTap: selectionMode
                                      ? () {
                                          setState(() {
                                            if (isSelected) {
                                              selectedIds.remove(docId);
                                            } else {
                                              selectedIds.add(docId);
                                            }
                                          });
                                        }
                                      : null,
                                  leading: selectionMode
                                      ? Checkbox(
                                          value: isSelected,
                                          onChanged: (v) {
                                            setState(() {
                                              if (v == true) {
                                                selectedIds.add(docId);
                                              } else {
                                                selectedIds.remove(docId);
                                              }
                                            });
                                          },
                                        )
                                      : CircleAvatar(
                                          child: Text(
                                            category.characters.first,
                                          ),
                                        ),
                                  title: Text(
                                    '$category • \$${amount.toStringAsFixed(2)}',
                                  ),
                                  subtitle: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      if (note.isNotEmpty) Text(note),
                                      const SizedBox(height: 2),
                                      Text(
                                        _fmtTimestamp(createdAt),
                                        style: const TextStyle(fontSize: 12),
                                      ),
                                    ],
                                  ),
                                  trailing: selectionMode
                                      ? null
                                      : IconButton(
                                          icon: const Icon(
                                            Icons.delete_outline,
                                          ),
                                          onPressed: () => _deleteWithUndo(
                                            uid: uid,
                                            doc: doc,
                                          ),
                                        ),
                                );
                              },
                            ),
                    ),

                    if (selectionMode)
                      SafeArea(
                        top: false,
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                          child: Row(
                            children: [
                              Expanded(
                                child: ElevatedButton.icon(
                                  onPressed: selectedIds.isEmpty
                                      ? null
                                      : () => _bulkDelete(uid),
                                  icon: const Icon(Icons.delete),
                                  label: Text('Delete (${selectedIds.length})'),
                                ),
                              ),
                              const SizedBox(width: 12),
                              OutlinedButton(
                                onPressed: () => setState(() {
                                  selectionMode = false;
                                  selectedIds.clear();
                                }),
                                child: const Text('Done'),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
