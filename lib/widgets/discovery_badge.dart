import 'package:feature_guide/api/tip_ledger.dart';
import 'package:flutter/material.dart';

/// Wraps a child widget and renders a small "New" dot in the top-right
/// corner while [tipId] has not yet been marked seen in [TipLedger].
///
/// Call [TipLedger().markSeen(tipId)] when the user interacts with the
/// wrapped feature — the badge clears itself because it listens to the
/// ledger's `seenNotifier`.
class DiscoveryBadgeWrapper extends StatelessWidget {
  final String tipId;
  final Widget child;

  /// Fill color of the "New" dot.
  final Color dotColor;

  /// Drop-shadow color behind the dot.
  final Color dotShadowColor;

  /// Diameter of the dot in logical pixels.
  final double size;

  /// Which corner of [child] the dot attaches to.
  final Alignment alignment;

  const DiscoveryBadgeWrapper({
    super.key,
    required this.tipId,
    required this.child,
    required this.dotColor,
    this.dotShadowColor = const Color(0x40000000),
    this.size = 8,
    this.alignment = Alignment.topRight,
  });

  @override
  Widget build(BuildContext context) {
    final notifier = TipLedger().seenNotifier(tipId);
    return ValueListenableBuilder<bool>(
      valueListenable: notifier,
      builder: (ctx, seen, _) {
        return Stack(
          clipBehavior: Clip.none,
          children: [
            child,
            if (!seen)
              Positioned(
                top:
                    alignment == Alignment.topRight ||
                        alignment == Alignment.topLeft
                    ? -size / 2
                    : null,
                bottom:
                    alignment == Alignment.bottomRight ||
                        alignment == Alignment.bottomLeft
                    ? -size / 2
                    : null,
                right:
                    alignment == Alignment.topRight ||
                        alignment == Alignment.bottomRight
                    ? -size / 2
                    : null,
                left:
                    alignment == Alignment.topLeft ||
                        alignment == Alignment.bottomLeft
                    ? -size / 2
                    : null,
                child: Container(
                  width: size,
                  height: size,
                  decoration: BoxDecoration(
                    color: dotColor,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: dotShadowColor,
                        blurRadius: 4,
                        offset: const Offset(0, 1),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}
