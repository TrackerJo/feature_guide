import 'dart:async';

import 'package:feature_guide/api/discovery_tip.dart';
import 'package:feature_guide/api/tip_ledger.dart';
import 'package:flutter/material.dart';

/// Singleton orchestrator for feature-discovery tips.
///
/// Replaces the ad-hoc `addPostFrameCallback` + `showDialog` pattern scattered
/// across screens. Screens emit [DiscoveryEvent]s; the service resolves which
/// (if any) registered [DiscoveryTip] wins, gates it against the session lock
/// + ledger + onboarding-complete flag, and runs its [DiscoveryPresentation].
///
/// Priorities:
///   - `critical`  → always evaluated, ignores session lock (e.g. permissions).
///   - `standard`  → respects session lock.
///   - `optional`  → respects session lock + onboarding-complete suppression
///     for `featureIntro` category tips.
///
/// Only one non-critical tip runs per session-lock window. The lock is cleared
/// on `AppLifecycleState.paused` via [onLifecycleResetSession].
class FeatureDiscoveryService {
  static final FeatureDiscoveryService _instance = FeatureDiscoveryService._();
  factory FeatureDiscoveryService() => _instance;
  FeatureDiscoveryService._();

  /// How long the app must be backgrounded before [onAppResumed] clears the
  /// session lock. Short foregrounds (switching apps briefly, answering a
  /// notification) should NOT re-open the tip queue.
  static const Duration backgroundResetThreshold = Duration(seconds: 10);

  final List<DiscoveryTip> _tips = [];
  Future<void>? _inFlight;
  bool _sessionLockHeld = false;
  DateTime? _lastPausedAt;

  /// Tip ids presented during the currently-executing `emit` call. Reset on
  /// each new emit. Exposed via [wasPresentedInCurrentEmit] so sibling tips in
  /// the same batch can mutex against each other (e.g. `always_location`
  /// skipping when `macro_streak_notifications` already fired this batch).
  final Set<String> _presentedThisEmit = <String>{};

  bool wasPresentedInCurrentEmit(String tipId) =>
      _presentedThisEmit.contains(tipId);

  /// Register a tip once at app start. Duplicate ids are ignored.
  void register(DiscoveryTip tip) {
    if (_tips.any((t) => t.id == tip.id)) return;
    _tips.add(tip);
  }

  void registerAll(Iterable<DiscoveryTip> tips) {
    for (final t in tips) {
      register(t);
    }
  }

  /// Remove all tips. Mostly for tests.
  @visibleForTesting
  void clear() {
    _tips.clear();
    _inFlight = null;
    _sessionLockHeld = false;
    _lastPausedAt = null;
  }

  /// Record the moment the app went to background. Called from
  /// [WidgetsBindingObserver.didChangeAppLifecycleState] on
  /// `AppLifecycleState.paused`.
  void onAppPaused() {
    _lastPausedAt = DateTime.now();
  }

  /// On foreground resume, clear the session lock if the app was backgrounded
  /// for at least [backgroundResetThreshold]. Short foregrounds (quickly
  /// checking a notification, swiping to another app and back) preserve the
  /// lock so the same tip doesn't re-fire mid-interaction.
  ///
  /// The lock clear is what lets the next `emit` (typically
  /// `menu_screen.onStartupTick` which fires on resume) present a fresh tip.
  void onAppResumed() {
    final pausedAt = _lastPausedAt;
    _lastPausedAt = null;
    if (pausedAt == null) return;
    if (DateTime.now().difference(pausedAt) >= backgroundResetThreshold) {
      _sessionLockHeld = false;
    }
  }

  /// Emit a semantic event. Evaluates every tip whose `triggers` include the
  /// event, in priority + order, and presents the first eligible one.
  ///
  /// Emits are serialized: if another emit is mid-presentation, this one
  /// waits for it to finish instead of dropping. That matters during app
  /// startup when `menu_screen.onStartupTick` and `home_screen.onHomeResumed`
  /// both fire in the same frame — previously the second was dropped,
  /// swallowing the what\'s-new sheet on fresh install.
  Future<bool> emit(
    BuildContext context,
    DiscoveryEvent event,
    DiscoveryContext ctx,
  ) async {
    if (event == DiscoveryEvent.onSessionReset) {
      _sessionLockHeld = false;
      return false;
    }

    // Wait for any in-flight emit to finish so we serialize cleanly instead
    // of silently dropping. Cap attempts to avoid pathological loops.
    for (int attempt = 0; attempt < 5 && _inFlight != null; attempt++) {
      try {
        await _inFlight;
      } catch (_) {
        // ignore; prior emit errors shouldn\'t poison this one
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
    DiscoveryEvent event,
    DiscoveryContext ctx,
  ) async {
    final ledger = TipLedger();
    if (!ledger.isInitialized) {
      return false;
    }

    // Refresh onboarding-complete gate so in-session streak/launch bumps take
    // effect the next time a feature-intro tip would otherwise fire.

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
      } catch (e) {
        continue;
      }
      if (!context.mounted) return anyPresented;

      await tip.markAsSeenLegacy?.call();
      if (!context.mounted) return anyPresented;
      final presented = await tip.presentation.present(context, tip, ctx);
      if (!presented) continue;

      if (tip.oneShot) await ledger.markSeen(tip.id);
      anyPresented = true;
      _presentedThisEmit.add(tip.id);

      // Non-critical tips claim the session lock + stop the chain.
      // Critical tips (permissions, data-disclosure) can run in sequence —
      // e.g. onMealLogged may fire health_apps_sync → macro_streak → always_location.
      if (tip.priority != DiscoveryPriority.critical) {
        _sessionLockHeld = true;
        return true;
      }
    }
    return anyPresented;
  }

  /// Clear the session lock (called on `AppLifecycleState.paused`).
  void onLifecycleResetSession() {
    _sessionLockHeld = false;
  }

  bool _gated(DiscoveryTip tip, TipLedger ledger) {
    // if (tip.id == "menu_filter_info") {
    //   logger.info('FeatureDiscovery: ${tip.id} bypassing gates for testing');
    //   return false;
    // }
    if (tip.oneShot && ledger.hasSeen(tip.id)) {
      return true;
    }
    if (tip.priority == DiscoveryPriority.tip && _sessionLockHeld) {
      return true;
    }
    // if (tip.category == DiscoveryCategory.featureIntro &&
    //     ledger.onboardingComplete) {
    //   logger.info(
    //     'FeatureDiscovery: ${tip.id} skipped - featureIntro and onboarding complete',
    //   );
    //   return true;
    // }

    return false;
  }
}
