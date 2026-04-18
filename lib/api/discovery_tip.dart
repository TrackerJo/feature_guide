import 'package:flutter/material.dart';

/// Context passed to a tip's eligibility check and its presentation.
///
/// Carries the generic runtime state a tip might need to decide whether to
/// fire — the current app-launch count, plus an arbitrary [data] map for
/// consumer-defined extras (e.g. a view counter, a feature flag).
class DiscoveryContext {
  /// Total app launches since install, incremented by the consumer app.
  /// Useful for "show on the 3rd launch" style rules.
  final int appLaunches;

  /// Arbitrary consumer-supplied extras. Prefer [read] for typed access.
  final Map<String, dynamic>? data;

  const DiscoveryContext({this.appLaunches = 0, this.data});

  /// Typed accessor for a value in [data]. Returns `null` if missing or if
  /// the stored value is not a `T`.
  T? read<T>(String key) {
    final value = data?[key];
    return value is T ? value : null;
  }
}

/// Lower value == evaluated first when multiple tips match the same event.
///
/// - [critical]: always evaluated, ignores the session lock, and can chain
///   with other critical tips in a single emit. Use for permission prompts
///   and data-disclosure notices.
/// - [standard]: respects the session lock; when it fires it claims the lock
///   and ends the chain for that emit.
/// - [optional]: behaves like [standard] but intended as a lower-weight tier
///   for nice-to-have hints.
/// - [tip]: respects the session lock AND is suppressed by a held lock. Use
///   for lightweight coach marks that should never stack on top of something
///   else the user just dismissed.
enum DiscoveryPriority { critical, standard, optional, tip }

/// Renders a tip. Subclass for a new presentation style, or use the built-in
/// [ModalPresentation] / [InlinePresentation] escape hatches.
///
/// Presentations are intentionally untyped on the event parameter (they
/// accept a raw [DiscoveryTip]) because a presentation's job is to render,
/// not to reason about which consumer event triggered the tip.
abstract class DiscoveryPresentation {
  const DiscoveryPresentation();

  /// Return `true` if the presentation actually rendered. A `false` return
  /// (e.g. a coach mark whose anchor wasn't mounted in time) means the tip
  /// should not be marked as seen and the emit loop may continue.
  Future<bool> present(
    BuildContext context,
    DiscoveryTip tip,
    DiscoveryContext ctx,
  );
}

/// Renders a modal dialog via `showDialog`. The [build] callback receives the
/// dialog's `BuildContext` and the emitting [DiscoveryContext] so the modal
/// body can read `ctx.data`, close itself, etc.
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
/// (e.g. an existing `showMyCustomSheet` function). The [run] callback is
/// responsible for rendering and returning `true` when something was shown.
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

/// A single feature-discovery entry. Parameterized on [E] — the consumer-
/// defined event type (typically an `enum`) used to match [triggers].
///
/// Example:
/// ```dart
/// enum AppEvent { onStartupTick, onProductViewed }
///
/// DiscoveryTip<AppEvent>(
///   id: 'welcome_banner',
///   priority: DiscoveryPriority.standard,
///   triggers: {AppEvent.onStartupTick},
///   shouldShow: (ctx) async => ctx.appLaunches >= 2,
///   presentation: BannerPresentation(
///     title: 'Welcome back!',
///     body: 'Tap the star icon to favorite a product.',
///     cardColor: Colors.white,
///     accentColor: Colors.indigo,
///   ),
/// );
/// ```
class DiscoveryTip<E extends Object> {
  /// Stable id used by [TipLedger] to remember whether the tip has been seen.
  final String id;

  /// Evaluation priority. See [DiscoveryPriority].
  final DiscoveryPriority priority;

  /// Sort key within a single priority bucket (lower = earlier).
  final int order;

  /// Events that trigger evaluation of this tip.
  final Set<E> triggers;

  /// If true, the tip is skipped once `ledger.hasSeen(id)` is true.
  final bool oneShot;

  /// Eligibility check run after the ledger and session gates pass. Return
  /// `false` to skip this tip for the current emit without marking it seen.
  final Future<bool> Function(DiscoveryContext ctx) shouldShow;

  /// How to render the tip when it wins.
  final DiscoveryPresentation presentation;

  const DiscoveryTip({
    required this.id,
    required this.priority,
    required this.triggers,
    required this.shouldShow,
    required this.presentation,
    this.order = 100,
    this.oneShot = true,
  });
}
