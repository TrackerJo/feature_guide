import 'dart:async';

import 'package:feature_guide/api/discovery_tip.dart';
import 'package:feature_guide/api/tip_ledger.dart';
import 'package:flutter/material.dart';

/// Orchestrates feature-discovery tips. Parameterized on [E] — the consumer-
/// defined event type (typically an `enum`) whose values are emitted from
/// screens as `emit(context, MyEvent.onFoo, ctx)`.
///
/// Usage (typically a single instance per app, held in a top-level `final`
/// or exposed through your DI / provider framework):
///
/// ```dart
/// enum AppEvent { onStartupTick, onProductViewed }
///
/// final discovery = FeatureDiscoveryService<AppEvent>()
///   ..registerAll([
///     DiscoveryTip<AppEvent>(
///       id: 'welcome_banner',
///       priority: DiscoveryPriority.standard,
///       triggers: {AppEvent.onStartupTick},
///       shouldShow: (ctx) async => ctx.appLaunches >= 2,
///       presentation: BannerPresentation(/* ... */),
///     ),
///   ]);
/// ```
///
/// **Priorities:**
/// - `critical` — always evaluated, ignores session lock, can chain with
///   other critical tips in a single emit (e.g. permissions, data disclosures).
/// - `standard` / `optional` — respect the session lock; claim the lock and
///   end the chain when they fire.
/// - `tip` — respects the session lock AND is suppressed by a held lock.
///
/// Only one non-critical tip runs per session-lock window. The lock is
/// cleared automatically when [onAppResumed] detects a background long
/// enough (see [backgroundResetThreshold]), or manually via [resetSession].
class FeatureDiscoveryService<E extends Object> {
  /// How long the app must stay backgrounded before [onAppResumed] clears
  /// the session lock. Short foregrounds (quickly checking a notification,
  /// answering a call) should NOT re-open the tip queue.
  final Duration backgroundResetThreshold;

  FeatureDiscoveryService({
    this.backgroundResetThreshold = const Duration(seconds: 10),
  });

  final List<DiscoveryTip<E>> _tips = [];
  Future<void>? _inFlight;
  bool _sessionLockHeld = false;
  DateTime? _lastPausedAt;

  /// Tip ids presented during the currently-executing [emit] call. Reset on
  /// each new emit. Exposed via [wasPresentedInCurrentEmit] so sibling tips
  /// in the same batch can mutex against each other.
  final Set<String> _presentedThisEmit = <String>{};

  /// Whether [tipId] has already been presented during the current [emit]
  /// call. Useful inside a tip's `shouldShow` to avoid piling tips on top of
  /// one another within a single trigger.
  bool wasPresentedInCurrentEmit(String tipId) =>
      _presentedThisEmit.contains(tipId);

  /// Register a tip once at app start. Duplicate ids are ignored.
  void register(DiscoveryTip<E> tip) {
    if (_tips.any((t) => t.id == tip.id)) return;
    _tips.add(tip);
  }

  /// Register every tip in [tips]. Convenience for bulk registration.
  void registerAll(Iterable<DiscoveryTip<E>> tips) {
    for (final t in tips) {
      register(t);
    }
  }

  /// Drop every registered tip and reset internal state. Mainly for tests.
  @visibleForTesting
  void clear() {
    _tips.clear();
    _inFlight = null;
    _sessionLockHeld = false;
    _lastPausedAt = null;
    _presentedThisEmit.clear();
  }

  /// Record the moment the app went to background. Call from
  /// `WidgetsBindingObserver.didChangeAppLifecycleState` on
  /// `AppLifecycleState.paused`.
  void onAppPaused() {
    _lastPausedAt = DateTime.now();
  }

  /// On foreground resume, clear the session lock if the app was backgrounded
  /// for at least [backgroundResetThreshold]. Short foregrounds preserve the
  /// lock so a tip the user just dismissed doesn't re-fire mid-interaction.
  void onAppResumed() {
    final pausedAt = _lastPausedAt;
    _lastPausedAt = null;
    if (pausedAt == null) return;
    if (DateTime.now().difference(pausedAt) >= backgroundResetThreshold) {
      _sessionLockHeld = false;
    }
  }

  /// Manually clear the session lock so the next eligible non-critical tip
  /// can fire. Use when a lifecycle event outside the app's pause/resume
  /// cycle should re-open the tip queue (e.g. the user completed onboarding).
  void resetSession() {
    _sessionLockHeld = false;
  }

  /// Emit an event. Evaluates every tip whose `triggers` contain [event], in
  /// priority + order, and presents the first eligible one (or a chain of
  /// critical tips).
  ///
  /// Emits are serialized: if another emit is mid-presentation, this call
  /// waits for it to finish instead of dropping, so two events that fire in
  /// the same frame (e.g. a startup tick and a resume tick) won't race.
  ///
  /// Returns `true` if at least one tip was presented.
  Future<bool> emit(
    BuildContext context,
    E event,
    DiscoveryContext ctx,
  ) async {
    // Wait for any in-flight emit to finish so we serialize cleanly instead
    // of silently dropping. Cap attempts to avoid pathological loops.
    for (int attempt = 0; attempt < 5 && _inFlight != null; attempt++) {
      try {
        await _inFlight;
      } catch (_) {
        // ignore; prior emit errors shouldn't poison this one
      }
    }

    if (!context.mounted) return false;

    final completer = Completer<void>();
    _inFlight = completer.future;
    try {
      return await _runEmit(context, event, ctx);
    } finally {
      completer.complete();
      _inFlight = null;
    }
  }

  Future<bool> _runEmit(
    BuildContext context,
    E event,
    DiscoveryContext ctx,
  ) async {
    final ledger = TipLedger();
    if (!ledger.isInitialized) {
      return false;
    }

    if (!context.mounted) return false;

    final candidates = _tips.where((t) => t.triggers.contains(event)).toList()
      ..sort((a, b) {
        final p = a.priority.index.compareTo(b.priority.index);
        if (p != 0) return p;
        return a.order.compareTo(b.order);
      });

    _presentedThisEmit.clear();
    bool anyPresented = false;
    for (final tip in candidates) {
      if (!context.mounted) return anyPresented;
      if (_gated(tip, ledger)) continue;
      try {
        if (!await tip.shouldShow(ctx)) continue;
      } catch (_) {
        continue;
      }
      if (!context.mounted) return anyPresented;

      final presented = await tip.presentation.present(context, tip, ctx);
      if (!presented) continue;

      if (tip.oneShot) await ledger.markSeen(tip.id);
      anyPresented = true;
      _presentedThisEmit.add(tip.id);

      // Non-critical tips claim the session lock and stop the chain.
      // Critical tips (permissions, data disclosures) run in sequence.
      if (tip.priority != DiscoveryPriority.critical) {
        _sessionLockHeld = true;
        return true;
      }
    }
    return anyPresented;
  }

  bool _gated(DiscoveryTip<E> tip, TipLedger ledger) {
    if (tip.oneShot && ledger.hasSeen(tip.id)) {
      return true;
    }
    if (tip.priority == DiscoveryPriority.tip && _sessionLockHeld) {
      return true;
    }
    return false;
  }
}
