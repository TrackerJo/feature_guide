import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Persistent "have we shown tip X?" store, backed by one `SharedPreferences`
/// key. Process-wide singleton — widgets like `DiscoveryBadgeWrapper` reach
/// for it directly via `TipLedger()`.
///
/// Call [init] once at app start (before running any emits). Pass a custom
/// [storageKey] if you want to isolate state per-flavor or avoid collision
/// with a previous install of the same package.
///
/// JSON shape written to the chosen key:
/// ```json
/// {
///   "version": 1,
///   "seen":     { "<tipId>": <epochMillis>, ... },
///   "asked":    { "<tipId>": <epochMillis>, ... },
///   "counters": { "<counter_key>": <int>, ... }
/// }
/// ```
class TipLedger {
  static const String defaultStorageKey = 'feature_guide_tip_ledger_v1';
  static const int _currentVersion = 1;

  static final TipLedger _instance = TipLedger._();
  factory TipLedger() => _instance;
  TipLedger._();

  bool _initialized = false;
  String _storageKey = defaultStorageKey;
  Map<String, int> _seen = {};
  Map<String, int> _asked = {};
  Map<String, int> _counters = {};

  final Map<String, ValueNotifier<bool>> _seenNotifiers = {};

  /// True once [init] has loaded (or started fresh).
  bool get isInitialized => _initialized;

  /// Storage key currently in use.
  String get storageKey => _storageKey;

  /// Load the ledger from `SharedPreferences`. Safe to call multiple times —
  /// subsequent calls are no-ops unless the key changes, in which case the
  /// ledger re-loads against the new key.
  ///
  /// [storageKey] — override to isolate state (e.g. per flavor or per user).
  Future<void> init({String storageKey = defaultStorageKey}) async {
    if (_initialized && _storageKey == storageKey) return;
    _storageKey = storageKey;
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_storageKey);

    if (raw != null) {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      _seen = _readIntMap(decoded['seen']);
      _asked = _readIntMap(decoded['asked']);
      _counters = _readIntMap(decoded['counters']);
    } else {
      _seen = {};
      _asked = {};
      _counters = {};
    }

    _initialized = true;
  }

  // ---------------------------------------------------------------------------
  // Query
  // ---------------------------------------------------------------------------

  /// Whether [tipId] has been marked seen via [markSeen].
  bool hasSeen(String tipId) => _seen.containsKey(tipId);

  /// Whether [tipId] has been marked asked via [markAsked] (e.g. a permission
  /// prompt was shown, regardless of user's answer).
  bool hasBeenAsked(String tipId) => _asked.containsKey(tipId);

  /// Current value of a named counter, or 0 if never set.
  int counter(String key) => _counters[key] ?? 0;

  /// `ValueNotifier` that flips to `true` once [markSeen] fires for [tipId].
  /// Listenable UIs (e.g. a "New" badge) can subscribe to auto-clear without
  /// explicit wiring.
  ValueNotifier<bool> seenNotifier(String tipId) {
    return _seenNotifiers.putIfAbsent(
      tipId,
      () => ValueNotifier<bool>(hasSeen(tipId)),
    );
  }

  // ---------------------------------------------------------------------------
  // Mutate
  // ---------------------------------------------------------------------------

  /// Mark [tipId] as seen and persist. No-op if already marked.
  Future<void> markSeen(String tipId) async {
    if (_seen.containsKey(tipId)) return;
    _seen[tipId] = DateTime.now().millisecondsSinceEpoch;
    _seenNotifiers[tipId]?.value = true;
    await _persist();
  }

  /// Mark [tipId] as asked and persist. No-op if already marked.
  Future<void> markAsked(String tipId) async {
    if (_asked.containsKey(tipId)) return;
    _asked[tipId] = DateTime.now().millisecondsSinceEpoch;
    await _persist();
  }

  /// Clear the seen flag for [tipId] (re-enables the tip on its next emit).
  Future<void> clearSeen(String tipId) async {
    if (_seen.remove(tipId) != null) {
      _seenNotifiers[tipId]?.value = false;
      await _persist();
    }
  }

  /// Overwrite the value of a named counter.
  Future<void> setCounter(String key, int value) async {
    _counters[key] = value;
    await _persist();
  }

  /// Increment a named counter by one and return the new value.
  Future<int> incCounter(String key) async {
    final next = (_counters[key] ?? 0) + 1;
    _counters[key] = next;
    await _persist();
    return next;
  }

  /// Shallow copy of internal state. Useful for debugging / exporting.
  Map<String, dynamic> dump() => {
    'version': _currentVersion,
    'seen': Map<String, int>.from(_seen),
    'asked': Map<String, int>.from(_asked),
    'counters': Map<String, int>.from(_counters),
  };

  /// Reset all in-memory and persisted state. Test-only helper — calling
  /// this in production will wipe the user's real ledger.
  @visibleForTesting
  Future<void> resetForTests() async {
    _seen.clear();
    _asked.clear();
    _counters.clear();
    for (final n in _seenNotifiers.values) {
      n.value = false;
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_storageKey);
    _initialized = false;
  }

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
