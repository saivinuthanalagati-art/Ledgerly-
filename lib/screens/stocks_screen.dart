import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

class StocksScreen extends StatefulWidget {
  const StocksScreen({super.key});

  @override
  State<StocksScreen> createState() => _StocksScreenState();
}

enum StockSort { pinnedFirst, alphabetic, changePctDesc, priceDesc }

class _StocksScreenState extends State<StocksScreen> {
  static const String _finnhubApiKey =String.fromEnvironment('FINNHUB_API_KEY');
  static const String _base = 'https://finnhub.io/api/v1';

  final _addCtrl = TextEditingController();
  final _searchCtrl = TextEditingController();
  Timer? _debounce;

  bool _loadingQuotes = false;
  bool _loadingSearch = false;
  String _error = '';

  DateTime? _lastUpdated;

  StockSort _sort = StockSort.pinnedFirst;

  final Map<String, Quote> _quotes = {};

  List<SearchResult> _results = [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _refreshFromFirestore(),
    );
  }

  @override
  void dispose() {
    _addCtrl.dispose();
    _searchCtrl.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  String _normSymbol(String raw) => raw.trim().toUpperCase();

  CollectionReference<Map<String, dynamic>> _watchlistRef(String uid) {
    return FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('watchlist');
  }

  Future<Map<String, dynamic>> _getJson(Uri uri) async {
    final res = await http.get(uri);
    if (res.statusCode != 200) {
      throw Exception('HTTP ${res.statusCode}: ${res.body}');
    }
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  Future<Quote> _fetchQuote(String symbol) async {
    final uri = Uri.parse('$_base/quote?symbol=$symbol&token=$_finnhubApiKey');
    final m = await _getJson(uri);

    final current = (m['c'] as num?)?.toDouble() ?? 0;
    final change = (m['d'] as num?)?.toDouble() ?? 0;
    final changePct = (m['dp'] as num?)?.toDouble() ?? 0;
    final high = (m['h'] as num?)?.toDouble() ?? 0;
    final low = (m['l'] as num?)?.toDouble() ?? 0;
    final open = (m['o'] as num?)?.toDouble() ?? 0;
    final prevClose = (m['pc'] as num?)?.toDouble() ?? 0;

    if (current == 0 && prevClose == 0) {
      throw Exception(
        'No quote for "$symbol". Use a real ticker like AAPL / MSFT / TSLA.',
      );
    }

    return Quote(
      symbol: symbol,
      current: current,
      change: change,
      changePct: changePct,
      open: open,
      high: high,
      low: low,
      prevClose: prevClose,
      fetchedAt: DateTime.now(),
    );
  }

  Future<List<SearchResult>> _search(String query) async {
    final q = query.trim();
    if (q.isEmpty) return [];

    final uri = Uri.parse(
      '$_base/search?q=${Uri.encodeComponent(q)}&token=$_finnhubApiKey',
    );
    final data = await _getJson(uri);

    final raw = (data['result'] as List<dynamic>? ?? []);
    final out = <SearchResult>[];
    for (final item in raw) {
      if (item is! Map) continue;
      final symbol = (item['symbol'] ?? '').toString().trim();
      final desc = (item['description'] ?? '').toString().trim();
      final type = (item['type'] ?? '').toString().trim();

      if (symbol.isEmpty) continue;
      if (symbol.contains(':')) continue; // e.g. foreign listings
      out.add(
        SearchResult(
          symbol: symbol.toUpperCase(),
          description: desc,
          type: type,
        ),
      );
      if (out.length >= 10) break;
    }
    return out;
  }

  Future<void> _refreshFromFirestore() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    setState(() {
      _loadingQuotes = true;
      _error = '';
    });

    try {
      final wl = await _watchlistRef(user.uid).get();
      final symbols = wl.docs.map((d) => d.id).toList();

      if (symbols.isEmpty) {
        setState(() {
          _quotes.clear();
          _lastUpdated = null;
        });
        return;
      }

      final results = await Future.wait(symbols.map(_fetchQuote));

      setState(() {
        for (final q in results) {
          _quotes[q.symbol] = q;
        }
        _lastUpdated = DateTime.now();
      });
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loadingQuotes = false);
    }
  }

  Future<void> _addTicker(String uid, String symbol) async {
    final s = _normSymbol(symbol);
    if (s.isEmpty) return;

    await _watchlistRef(uid).doc(s).set({
      'symbol': s,
      'pinned': false,
      'createdAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    _addCtrl.clear();
    _searchCtrl.clear();
    setState(() {
      _results = [];
      _error = '';
    });

    await _refreshFromFirestore();
  }

  Future<void> _removeTicker(String uid, String symbol) async {
    await _watchlistRef(uid).doc(symbol).delete();
    setState(() => _quotes.remove(symbol));
  }

  Future<void> _togglePin(String uid, String symbol, bool currentPinned) async {
    await _watchlistRef(
      uid,
    ).doc(symbol).set({'pinned': !currentPinned}, SetOptions(merge: true));
  }

  void _onSearchChanged(String v) {
    _debounce?.cancel();
    final text = v.trim();

    if (text.isEmpty) {
      setState(() => _results = []);
      return;
    }

    _debounce = Timer(const Duration(milliseconds: 350), () async {
      setState(() {
        _loadingSearch = true;
        _error = '';
      });

      try {
        final found = await _search(text);
        if (!mounted) return;
        setState(() => _results = found);
      } catch (e) {
        if (!mounted) return;
        setState(() => _error = 'Search failed: $e');
      } finally {
        if (!mounted) {
          setState(() => _loadingSearch = false);
        }
      }
    });
  }

  String _fmt(num? v, {int decimals = 2}) {
    if (v == null) return '--';
    return v.toDouble().toStringAsFixed(decimals);
  }

  List<String> _buildInsights(List<WatchItem> items) {
    if (items.isEmpty) return ['Add a few tickers to build your watchlist.'];

    final withQuotes = items.where((i) => _quotes[i.symbol] != null).toList();
    if (withQuotes.isEmpty) return ['Tap Refresh to load quotes.'];

    withQuotes.sort((a, b) {
      final ap = _quotes[a.symbol]!.changePct;
      final bp = _quotes[b.symbol]!.changePct;
      return bp.compareTo(ap);
    });

    final best = withQuotes.first;
    final worst = withQuotes.last;

    final bestQ = _quotes[best.symbol]!;
    final worstQ = _quotes[worst.symbol]!;

    final insights = <String>[
      'Top mover: ${best.symbol} (${bestQ.changePct >= 0 ? '+' : ''}${bestQ.changePct.toStringAsFixed(2)}%).',
    ];

    if (withQuotes.length > 1) {
      insights.add(
        'Biggest drop: ${worst.symbol} (${worstQ.changePct >= 0 ? '+' : ''}${worstQ.changePct.toStringAsFixed(2)}%).',
      );
    }

    final volatile = withQuotes
        .where((i) => _quotes[i.symbol]!.changePct.abs() >= 3)
        .toList();
    if (volatile.isNotEmpty) {
      insights.add(
        'Volatility alert: ${volatile.map((e) => e.symbol).take(4).join(', ')} moved ≥ 3% today.',
      );
    }

    if (items.length == 1) {
      insights.add(
        'Tip: add 3–5 tickers so you can compare relative performance.',
      );
    } else if (items.length >= 5) {
      insights.add(
        'Nice: you’re tracking multiple tickers—easier to spot patterns.',
      );
    }

    insights.add('Reminder: informational only (not financial advice).');
    return insights;
  }

  List<WatchItem> _applySort(List<WatchItem> items) {
    final out = List<WatchItem>.from(items);

    int cmpAlpha(WatchItem a, WatchItem b) => a.symbol.compareTo(b.symbol);

    switch (_sort) {
      case StockSort.pinnedFirst:
        out.sort((a, b) {
          if (a.pinned != b.pinned) return a.pinned ? -1 : 1;
          return cmpAlpha(a, b);
        });
        return out;

      case StockSort.alphabetic:
        out.sort(cmpAlpha);
        return out;

      case StockSort.changePctDesc:
        out.sort((a, b) {
          final aq = _quotes[a.symbol]?.changePct;
          final bq = _quotes[b.symbol]?.changePct;
          final av = aq ?? -999999;
          final bv = bq ?? -999999;
          final c = bv.compareTo(av);
          return c != 0 ? c : cmpAlpha(a, b);
        });
        return out;

      case StockSort.priceDesc:
        out.sort((a, b) {
          final aq = _quotes[a.symbol]?.current;
          final bq = _quotes[b.symbol]?.current;
          final av = aq ?? -999999;
          final bv = bq ?? -999999;
          final c = bv.compareTo(av);
          return c != 0 ? c : cmpAlpha(a, b);
        });
        return out;
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser!;
    final uid = user.uid;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Stocks'),
        actions: [
          IconButton(
            tooltip: 'Refresh quotes',
            onPressed: _loadingQuotes ? null : _refreshFromFirestore,
            icon: _loadingQuotes
                ? const SizedBox(
                    height: 18,
                    width: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh),
          ),
        ],
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: _watchlistRef(
          uid,
        ).orderBy('createdAt', descending: false).snapshots(),
        builder: (context, snap) {
          final docs = snap.data?.docs ?? [];
          final watch = docs.map((d) {
            final pinned = (d.data()['pinned'] as bool?) ?? false;
            return WatchItem(symbol: d.id, pinned: pinned);
          }).toList();

          final sorted = _applySort(watch);
          final insights = _buildInsights(sorted);

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _addCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Quick add by ticker (e.g., AAPL)',
                      ),
                      onSubmitted: (_) => _addTicker(uid, _addCtrl.text),
                    ),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton(
                    onPressed: () => _addTicker(uid, _addCtrl.text),
                    child: const Text('Add'),
                  ),
                ],
              ),

              const SizedBox(height: 12),

              TextField(
                controller: _searchCtrl,
                onChanged: _onSearchChanged,
                decoration: InputDecoration(
                  labelText: 'Search company/ticker (recommended)',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: _loadingSearch
                      ? const Padding(
                          padding: EdgeInsets.all(12),
                          child: SizedBox(
                            height: 16,
                            width: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        )
                      : (_searchCtrl.text.trim().isEmpty
                            ? null
                            : IconButton(
                                icon: const Icon(Icons.clear),
                                onPressed: () {
                                  _searchCtrl.clear();
                                  setState(() => _results = []);
                                },
                              )),
                ),
              ),

              if (_results.isNotEmpty) ...[
                const SizedBox(height: 10),
                Card(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Column(
                    children: _results.map((r) {
                      return ListTile(
                        title: Text(
                          r.symbol,
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        subtitle: Text(
                          r.description.isEmpty ? r.type : r.description,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        trailing: const Icon(Icons.add_circle_outline),
                        onTap: () => _addTicker(uid, r.symbol),
                      );
                    }).toList(),
                  ),
                ),
              ],

              const SizedBox(height: 12),

              if (_error.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    _error,
                    style: const TextStyle(color: Colors.red),
                  ),
                ),

              Row(
                children: [
                  Text(
                    'Watchlist (${sorted.length})',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const Spacer(),
                  DropdownButton<StockSort>(
                    value: _sort,
                    onChanged: (v) => setState(() => _sort = v ?? _sort),
                    items: const [
                      DropdownMenuItem(
                        value: StockSort.pinnedFirst,
                        child: Text('Pinned first'),
                      ),
                      DropdownMenuItem(
                        value: StockSort.alphabetic,
                        child: Text('A → Z'),
                      ),
                      DropdownMenuItem(
                        value: StockSort.changePctDesc,
                        child: Text('% change'),
                      ),
                      DropdownMenuItem(
                        value: StockSort.priceDesc,
                        child: Text('Price'),
                      ),
                    ],
                  ),
                ],
              ),

              if (_lastUpdated != null)
                Padding(
                  padding: const EdgeInsets.only(top: 4, bottom: 8),
                  child: Text(
                    'Last updated: ${_lastUpdated!.hour.toString().padLeft(2, '0')}:${_lastUpdated!.minute.toString().padLeft(2, '0')}',
                    style: const TextStyle(fontSize: 12),
                  ),
                ),

              if (sorted.isEmpty)
                const Padding(
                  padding: EdgeInsets.only(top: 16),
                  child: Center(child: Text('No tickers yet. Add one above.')),
                )
              else
                ...sorted.map((item) {
                  final q = _quotes[item.symbol];
                  final tone = q == null
                      ? Colors.indigo
                      : (q.changePct >= 1
                            ? Colors.green
                            : (q.changePct <= -1 ? Colors.red : Colors.indigo));

                  return Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: tone.withValues(alpha: 0.35)),
                      color: tone.withValues(alpha: 0.08),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Row(
                                children: [
                                  Text(
                                    item.symbol,
                                    style: const TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  if (item.pinned)
                                    const Icon(Icons.push_pin, size: 16),
                                ],
                              ),
                            ),
                            IconButton(
                              tooltip: item.pinned ? 'Unpin' : 'Pin',
                              onPressed: () =>
                                  _togglePin(uid, item.symbol, item.pinned),
                              icon: Icon(
                                item.pinned
                                    ? Icons.push_pin
                                    : Icons.push_pin_outlined,
                              ),
                            ),
                            IconButton(
                              tooltip: 'Remove',
                              onPressed: () => _removeTicker(uid, item.symbol),
                              icon: const Icon(Icons.close),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        if (q == null)
                          const Text('Tap refresh to load quote.')
                        else ...[
                          Text(
                            '\$${_fmt(q.current)}  '
                            '(${q.change >= 0 ? '+' : ''}${_fmt(q.change)} / '
                            '${q.changePct >= 0 ? '+' : ''}${_fmt(q.changePct)}%)',
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 10,
                            runSpacing: 6,
                            children: [
                              _chip('O', _fmt(q.open)),
                              _chip('H', _fmt(q.high)),
                              _chip('L', _fmt(q.low)),
                              _chip('PC', _fmt(q.prevClose)),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(_aiCardLine(q)),
                        ],
                      ],
                    ),
                  );
                }),

              const SizedBox(height: 10),

              Card(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'AI-style insights',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 10),
                      ...insights.map(
                        (t) => Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('•  '),
                              Expanded(child: Text(t)),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 8),
              const Text(
                'Note: Informational insights only (not financial advice).',
                style: TextStyle(fontSize: 12),
              ),
            ],
          );
        },
      ),
    );
  }

  static Widget _chip(String label, String value) {
    return Chip(
      label: Text('$label $value'),
      visualDensity: VisualDensity.compact,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
    );
  }

  String _aiCardLine(Quote q) {
    final pct = q.changePct;
    if (pct.abs() >= 3) {
      return 'Large move today. Consider checking news/earnings before acting.';
    }
    if (pct >= 1) {
      return 'Up today. Don’t chase—stick to your plan and risk limits.';
    }
    if (pct <= -1) {
      return 'Down today. If you own it, decide based on long-term thesis, not emotion.';
    }
    return 'Quiet day. Good time to review fundamentals and your budgeting goals.';
  }
}

class WatchItem {
  final String symbol;
  final bool pinned;
  WatchItem({required this.symbol, required this.pinned});
}

class SearchResult {
  final String symbol;
  final String description;
  final String type;
  SearchResult({
    required this.symbol,
    required this.description,
    required this.type,
  });
}

class Quote {
  final String symbol;
  final double current;
  final double change;
  final double changePct;
  final double open;
  final double high;
  final double low;
  final double prevClose;
  final DateTime fetchedAt;

  Quote({
    required this.symbol,
    required this.current,
    required this.change,
    required this.changePct,
    required this.open,
    required this.high,
    required this.low,
    required this.prevClose,
    required this.fetchedAt,
  });
}
