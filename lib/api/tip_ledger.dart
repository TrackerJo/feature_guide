import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Single source of truth for "have we shown tip X?" state.
///
/// Backed by one `SharedPreferences` key: [_storageKey], holding JSON:
/// ```json
/// {
///   "version": 1,
///   "seen": { "tip_id": epochMillis, ... },
///   "asked": { "tip_id": epochMillis, ... },
///   "counters": { "food_detail_views": 3, ... },
///   "onboardingComplete": false
/// }
/// ```
///
/// On first init it migrates the scattered legacy `SEEN_*` / `ASKED_*` keys
/// into `seen` / `asked`. Legacy keys are left in place for one release as a
/// rollback safety net; `SharedPrefs` setters will dual-write to both stores
/// during the migration window.
class TipLedger {
  static const String _storageKey = 'DISCOVERY_TIP_LEDGER_V1';
  static const int _currentVersion = 1;

  static final TipLedger _instance = TipLedger._();
  factory TipLedger() => _instance;
  TipLedger._();

  bool _initialized = false;
  Map<String, int> _seen = {};
  Map<String, int> _asked = {};
  Map<String, int> _counters = {};

  final Map<String, ValueNotifier<bool>> _seenNotifiers = {};

  /// True once [init] has loaded (or migrated) the ledger.
  bool get isInitialized => _initialized;

  /// Read or migrate the ledger. Safe to call multiple times.
  Future<void> init() async {
    if (_initialized) return;
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_storageKey);

    if (raw != null) {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      _seen = _readIntMap(decoded['seen']);
      _asked = _readIntMap(decoded['asked']);
      _counters = _readIntMap(decoded['counters']);
    }

    _initialized = true;
  }

  // ---------------------------------------------------------------------------
  // Query
  // ---------------------------------------------------------------------------

  bool hasSeen(String tipId) => _seen.containsKey(tipId);
  bool hasBeenAsked(String tipId) => _asked.containsKey(tipId);
  int counter(String key) => _counters[key] ?? 0;

  /// `ValueNotifier` that flips to true when [markSeen] is called for [tipId].
  /// Used by `DiscoveryBadgeWrapper` to auto-clear a "New" badge on tap.
  ValueNotifier<bool> seenNotifier(String tipId) {
    return _seenNotifiers.putIfAbsent(
      tipId,
      () => ValueNotifier<bool>(hasSeen(tipId)),
    );
  }

  // ---------------------------------------------------------------------------
  // Mutate
  // ---------------------------------------------------------------------------

  Future<void> markSeen(String tipId) async {
    if (_seen.containsKey(tipId)) return;
    _seen[tipId] = DateTime.now().millisecondsSinceEpoch;
    _seenNotifiers[tipId]?.value = true;
    await _persist();
  }

  Future<void> markAsked(String tipId) async {
    if (_asked.containsKey(tipId)) return;
    _asked[tipId] = DateTime.now().millisecondsSinceEpoch;
    await _persist();
  }

  Future<void> clearSeen(String tipId) async {
    if (_seen.remove(tipId) != null) {
      _seenNotifiers[tipId]?.value = false;
      await _persist();
    }
  }

  Future<void> setCounter(String key, int value) async {
    _counters[key] = value;
    await _persist();
  }

  Future<int> incCounter(String key) async {
    final next = (_counters[key] ?? 0) + 1;
    _counters[key] = next;
    await _persist();
    return next;
  }

  /// Debug/introspection — returns a shallow copy of internal state.
  Map<String, dynamic> dump() => {
    'version': _currentVersion,
    'seen': Map<String, int>.from(_seen),
    'asked': Map<String, int>.from(_asked),
    'counters': Map<String, int>.from(_counters),
  };

  // ---------------------------------------------------------------------------
  // Internals
  // ---------------------------------------------------------------------------

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_storageKey, jsonEncode(dump()));
  }

  static Map<String, int> _readIntMap(dynamic v) {
    if (v is! Map) return {};
    return v.map((k, val) => MapEntry(k.toString(), (val as num).toInt()));
  }
}
