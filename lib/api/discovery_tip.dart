import 'package:flutter/material.dart';

/// Semantic events screens emit to the [FeatureDiscoveryService].
///
/// Triggers are decoupled from screen lifecycle so no screen fires a dialog
/// directly — the service decides what (if anything) to surface based on
/// registered tips, priority, session lock, and onboarding state.
enum DiscoveryEvent {
  onStartupTick,
  onHomeResumed,
  onFoodDetailViewed,
  onMealDetailViewed,
  onLikeFoodTapped,
  onSaveMealTapped,
  onDiningHallMenuLoaded,
  onMealBuilt,
  onCustomMealStarted,
  onCustomFoodsMenuOpened,
  onMealLogged,
  onSessionReset,
  onMealFoodSelected,
  onMacroProgressViewed,
}

/// Lower value == evaluated first.
/// Tips are only shown once per session-lock window, but critical tips ignore the lock and are always evaluated. This allows important tips (e.g. permissions) to break through the noise, while less-critical tips
enum DiscoveryPriority { critical, standard, optional, tip }

/// Category used by [TipLedger.onboardingComplete] to suppress
/// feature-intro tips once the user has clearly onboarded.
enum DiscoveryCategory {
  featureIntro,
  permission,
  dataDisclosure,
  versionUpdate,
  feedback,
  promo,
}

/// Context passed to tip evaluation and presentation.
///
/// Kept structurally compatible with the legacy `StartupDialogContext` so
/// existing call sites continue to compile after the shim rewrite.
class DiscoveryContext {
  final int appLaunches;
  final int selectedIndex;
  final Function? callback;

  /// Arbitrary extras (e.g. foodDetailViewCount).
  final Map<String, dynamic>? data;

  const DiscoveryContext({
    this.appLaunches = 0,
    this.selectedIndex = 0,
    this.callback,
    this.data,
  });

  T? read<T>(String key) => data?[key] as T?;
}

/// Abstract presentation — modal, banner, coach mark, etc.
abstract class DiscoveryPresentation {
  const DiscoveryPresentation();

  /// Return `true` if the presentation actually rendered. A `false` return
  /// (e.g. anchor missing for a coach mark) means the tip should not be
  /// marked as seen.
  Future<bool> present(
    BuildContext context,
    DiscoveryTip tip,
    DiscoveryContext ctx,
  );
}

/// Renders a [DefaultDialog]-style modal via `showDialog`.
///
/// Builder receives the dialog `BuildContext` and the emitting
/// [DiscoveryContext] so the modal body can read `ctx.callback`, etc.
class ModalPresentation extends DiscoveryPresentation {
  final Widget Function(BuildContext dialogContext, DiscoveryContext ctx) build;
  final bool barrierDismissible;

  const ModalPresentation({
    required this.build,
    this.barrierDismissible = true,
  });

  @override
  Future<bool> present(
    BuildContext context,
    DiscoveryTip tip,
    DiscoveryContext ctx,
  ) async {
    await showDialog<void>(
      context: context,
      barrierDismissible: barrierDismissible,
      builder: (dialogCtx) => build(dialogCtx, ctx),
    );
    return true;
  }
}

/// Escape hatch for tips whose presentation is already implemented elsewhere
/// (e.g. an external service's `showX` method). Returns `true` if the run
/// function actually presented something.
class InlinePresentation extends DiscoveryPresentation {
  final Future<bool> Function(BuildContext context, DiscoveryContext ctx) run;

  const InlinePresentation(this.run);

  @override
  Future<bool> present(
    BuildContext context,
    DiscoveryTip tip,
    DiscoveryContext ctx,
  ) => run(context, ctx);
}

/// A single feature-discovery entry. Replaces the legacy `StartupDialog`.
class DiscoveryTip {
  final String id;
  final DiscoveryPriority priority;
  final DiscoveryCategory category;

  /// Sort key within a single priority bucket (lower = earlier).
  final int order;

  /// Events that trigger evaluation of this tip.
  final Set<DiscoveryEvent> triggers;

  /// If true, tip is skipped once `ledger.hasSeen(id)` is true.
  final bool oneShot;

  /// Eligibility check run after the ledger + session gates pass.
  final Future<bool> Function(DiscoveryContext ctx) shouldShow;

  /// The presentation to run when the tip wins.
  final DiscoveryPresentation presentation;

  /// Optional hook — called before `presentation.present` (e.g. to write a
  /// legacy SharedPrefs key during the migration window).
  final Future<void> Function()? markAsSeenLegacy;

  const DiscoveryTip({
    required this.id,
    required this.priority,
    required this.category,
    required this.triggers,
    required this.shouldShow,
    required this.presentation,
    this.order = 100,
    this.oneShot = true,
    this.markAsSeenLegacy,
  });
}
