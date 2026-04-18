import 'package:feature_guide/api/discovery_tip.dart';
import 'package:feature_guide/widgets/discovery_anchor.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Where the coach-mark bubble sits relative to the anchor widget.
enum CoachMarkPlacement { above, below, auto }

/// Visual style of the coach-mark bubble.
///
/// - [classic]: larger rounded card with a right-aligned "Got it" button.
/// - [compact]: pill-shaped single row with a tight ✕ dismiss circle. More
///   modern, takes less vertical space, dismisses via the close button or
///   the scrim.
enum CoachMarkStyle { classic, compact }

/// An arrow + text bubble overlay anchored to a widget's `GlobalKey`.
///
/// Dimmed scrim covers the rest of the screen; a cutout reveals the anchor
/// so the user visually connects the hint to the feature. Tap outside or
/// "Got it" to dismiss.
class DiscoveryCoachMark {
  final Color primaryColor;
  final Color backgroundColor;
  final Color border;
  final Color icon;

  const DiscoveryCoachMark({
    required this.primaryColor,
    required this.backgroundColor,
    required this.border,
    required this.icon,
  });

  /// Returns `true` if the overlay was actually shown, `false` if the anchor
  /// had no current context (screen changed / widget not mounted yet).
  Future<bool> show({
    required BuildContext context,
    required String anchorKey,
    required String message,
    String? title,
    String? dismissLabel,
    CoachMarkPlacement placement = CoachMarkPlacement.auto,
    CoachMarkStyle style = CoachMarkStyle.classic,
  }) async {
    final overlay = Overlay.of(context, rootOverlay: true);
    final screenSize = MediaQuery.of(context).size;

    // Poll the registry until the anchor is mounted, on-screen, AND stable
    // for two consecutive frames. Food / meal detail sheets animate in, so
    // the anchor's rect changes every frame during the transition — grabbing
    // a rect mid-animation leaves the highlight in the wrong place. Waiting
    // for the rect to stop moving guarantees the route finished animating.
    const pollInterval = Duration(milliseconds: 50);
    const pollTimeout = Duration(milliseconds: 2000);
    const stableRequired = 2;
    final deadline = DateTime.now().add(pollTimeout);
    Rect? anchorRect;
    Rect? lastRect;
    int stableCount = 0;
    while (DateTime.now().isBefore(deadline)) {
      if (!context.mounted) return false;
      final rect = DiscoveryAnchorRegistry.instance.rectFor(anchorKey);
      if (rect == null) {
        lastRect = null;
        stableCount = 0;
      } else {
        final onScreen =
            rect.bottom >= 0 &&
            rect.top <= screenSize.height &&
            rect.right >= 0 &&
            rect.left <= screenSize.width;
        if (!onScreen) {
          lastRect = null;
          stableCount = 0;
        } else {
          if (lastRect != null && _rectEquals(lastRect, rect)) {
            stableCount++;
            if (stableCount >= stableRequired) {
              anchorRect = rect;
              break;
            }
          } else {
            stableCount = 0;
          }
          lastRect = rect;
        }
      }
      await Future<void>.delayed(pollInterval);
    }
    if (anchorRect == null) {
      return false;
    }
    if (!context.mounted) return false;
    final resolvedRect = anchorRect;

    final resolved = placement == CoachMarkPlacement.auto
        ? (resolvedRect.center.dy > screenSize.height / 2
              ? CoachMarkPlacement.above
              : CoachMarkPlacement.below)
        : placement;

    final completer = _Completer();
    late OverlayEntry entry;
    entry = OverlayEntry(
      builder: (ctx) => _CoachMarkLayer(
        anchorRect: resolvedRect,
        placement: resolved,
        title: title,
        message: message,
        dismissLabel: dismissLabel ?? 'Got it',
        style: style,
        onDismiss: () {
          if (completer.done) return;
          completer.done = true;
          entry.remove();
        },
        primaryColor: primaryColor,
        backgroundColor: backgroundColor,
        border: border,
        icon: icon,
      ),
    );
    overlay.insert(entry);
    HapticFeedback.lightImpact();

    // Wait until dismissed.
    while (!completer.done) {
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    return true;
  }
}

class _Completer {
  bool done = false;
}

bool _rectEquals(Rect a, Rect b, {double epsilon = 0.5}) {
  return (a.left - b.left).abs() < epsilon &&
      (a.top - b.top).abs() < epsilon &&
      (a.right - b.right).abs() < epsilon &&
      (a.bottom - b.bottom).abs() < epsilon;
}

class _CoachMarkLayer extends StatelessWidget {
  final Rect anchorRect;
  final CoachMarkPlacement placement;
  final String? title;
  final String message;
  final String dismissLabel;
  final CoachMarkStyle style;
  final VoidCallback onDismiss;
  final Color primaryColor;
  final Color backgroundColor;
  final Color border;
  final Color icon;

  const _CoachMarkLayer({
    required this.anchorRect,
    required this.placement,
    required this.message,
    required this.dismissLabel,
    required this.style,
    required this.onDismiss,
    required this.primaryColor,
    required this.backgroundColor,
    required this.border,
    required this.icon,
    this.title,
  });

  @override
  Widget build(BuildContext context) {
    final screen = MediaQuery.of(context).size;
    const inset = 12.0;
    const arrowWidth = 16.0;
    const arrowHeight = 9.0;
    const gap = 6.0;
    final bubbleMaxWidth = style == CoachMarkStyle.compact ? 260.0 : 280.0;
    final bubbleBelow = placement == CoachMarkPlacement.below;

    final highlight = Rect.fromLTRB(
      anchorRect.left - 6,
      anchorRect.top - 6,
      anchorRect.right + 6,
      anchorRect.bottom + 6,
    );

    final bubble = style == CoachMarkStyle.compact
        ? _buildCompactBubble()
        : _buildClassicBubble();

    // Arrow is clamped so it stays within the screen insets, but still tries
    // to sit under the anchor's horizontal center.
    final arrowLeft = (anchorRect.center.dx - arrowWidth / 2).clamp(
      inset + 8.0,
      screen.width - inset - arrowWidth - 8.0,
    );

    return Stack(
      children: [
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onDismiss,
            child: CustomPaint(
              size: Size(screen.width, screen.height),
              painter: _ScrimPainter(highlight: highlight),
            ),
          ),
        ),
        // Arrow between anchor and bubble, tip pointing AT the anchor.
        // Painter draws the triangle with base on top and tip at bottom —
        // so rotate 180° when the bubble is below (tip must point up).
        Positioned(
          left: arrowLeft,
          top: bubbleBelow
              ? anchorRect.bottom + gap
              : anchorRect.top - gap - arrowHeight,
          child: IgnorePointer(
            child: Transform.rotate(
              angle: bubbleBelow ? 3.14159 : 0,
              child: CustomPaint(
                size: const Size(arrowWidth, arrowHeight),
                painter: _ArrowPainter(color: primaryColor),
              ),
            ),
          ),
        ),
        // Compact bubble: bounded max width, centered horizontally, pinned
        // directly to the arrow so they visually connect.
        Positioned(
          left: inset,
          right: inset,
          top: bubbleBelow ? anchorRect.bottom + gap + arrowHeight : null,
          bottom: bubbleBelow
              ? null
              : screen.height - anchorRect.top + gap + arrowHeight,
          child: Align(
            alignment: Alignment.center,
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: bubbleMaxWidth),
              child: bubble,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildClassicBubble() {
    return Material(
      color: Colors.transparent,
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 10, 10, 8),
        decoration: BoxDecoration(
          color: primaryColor,
          borderRadius: BorderRadius.circular(10),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.22),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (title != null) ...[
              Text(
                title!,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 2),
            ],
            Text(
              message,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12.5,
                height: 1.25,
              ),
            ),
            const SizedBox(height: 6),
            Align(
              alignment: Alignment.centerRight,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () {
                  HapticFeedback.mediumImpact();
                  onDismiss();
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    dismissLabel,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 11.5,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Pill-shaped single row: title/message on the left, a 22×22 ✕ close
  /// circle on the right. Tighter padding, no "Got it" button, no right-
  /// aligned action row — dismisses via the close button or the scrim.
  Widget _buildCompactBubble() {
    return Material(
      color: Colors.transparent,
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
        decoration: BoxDecoration(
          color: primaryColor,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: border, width: 1),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.22),
              blurRadius: 14,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Flexible(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (title != null) ...[
                    Text(
                      title!,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                        letterSpacing: 0.1,
                      ),
                    ),
                    const SizedBox(height: 1),
                  ],
                  Text(
                    message,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.95),
                      fontSize: 12.5,
                      height: 1.25,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () {
                HapticFeedback.mediumImpact();
                onDismiss();
              },
              child: Container(
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  // color: border,
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.close, color: icon, size: 16),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ScrimPainter extends CustomPainter {
  final Rect highlight;
  _ScrimPainter({required this.highlight});

  @override
  void paint(Canvas canvas, Size size) {
    final scrim = Paint()..color = Colors.black.withValues(alpha: 0.55);
    final path = Path()
      ..addRect(Rect.fromLTWH(0, 0, size.width, size.height))
      ..addRRect(RRect.fromRectAndRadius(highlight, const Radius.circular(12)))
      ..fillType = PathFillType.evenOdd;
    canvas.drawPath(path, scrim);
  }

  @override
  bool shouldRepaint(covariant _ScrimPainter old) => old.highlight != highlight;
}

class _ArrowPainter extends CustomPainter {
  final Color color;
  _ArrowPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..moveTo(0, 0)
      ..lineTo(size.width, 0)
      ..lineTo(size.width / 2, size.height)
      ..close();
    canvas.drawPath(path, Paint()..color = color);
  }

  @override
  bool shouldRepaint(covariant _ArrowPainter old) => old.color != color;
}

/// [DiscoveryPresentation] wrapper registered on a [DiscoveryTip].
///
/// The target widget must be wrapped in a [DiscoveryAnchor] with a matching
/// [anchorKey]. The anchor self-registers with [DiscoveryAnchorRegistry], so
/// there's no need to plumb `GlobalKey`s through `DiscoveryContext`.
class CoachMarkPresentation extends DiscoveryPresentation {
  /// String id matched against mounted `DiscoveryAnchor`s.
  final String anchorKey;
  final String message;
  final String? title;
  final String? dismissLabel;
  final CoachMarkPlacement placement;
  final CoachMarkStyle style;
  final Color primaryColor;
  final Color backgroundColor;
  final Color border;
  final Color icon;

  const CoachMarkPresentation({
    required this.anchorKey,
    required this.message,
    required this.primaryColor,
    required this.backgroundColor,
    required this.border,
    required this.icon,
    this.title,
    this.dismissLabel,
    this.placement = CoachMarkPlacement.auto,
    this.style = CoachMarkStyle.classic,
  });

  @override
  Future<bool> present(
    BuildContext context,
    DiscoveryTip tip,
    DiscoveryContext ctx,
  ) {
    return DiscoveryCoachMark(
      primaryColor: primaryColor,
      backgroundColor: backgroundColor,
      border: border,
      icon: icon,
    ).show(
      context: context,
      anchorKey: anchorKey,
      message: message,
      title: title,
      dismissLabel: dismissLabel,
      placement: placement,
      style: style,
    );
  }
}
