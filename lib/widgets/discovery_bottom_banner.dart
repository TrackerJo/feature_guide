import 'package:feature_guide/api/discovery_tip.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:overlay_support/overlay_support.dart';

/// Non-blocking top-anchored banner for feature hints.
///
/// Auto-dismisses after [duration], or on swipe / action tap. Does not block
/// underlying UI — the user can keep scrolling, tapping, etc.
class DiscoveryBottomBanner extends StatelessWidget {
  final String title;
  final String body;
  final String? actionLabel;
  final VoidCallback? onAction;
  final VoidCallback onDismiss;
  final IconData? icon;
  final Color backgroundColor;
  final Color primaryColor;

  const DiscoveryBottomBanner({
    super.key,
    required this.title,
    required this.body,
    required this.onDismiss,
    required this.backgroundColor,
    required this.primaryColor,
    this.actionLabel,
    this.onAction,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
        child: Material(
          color: Colors.transparent,
          child: Container(
            decoration: BoxDecoration(
              color: backgroundColor,
              borderRadius: BorderRadius.circular(14),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.18),
                  blurRadius: 16,
                  offset: const Offset(0, 4),
                ),
              ],
              border: Border.all(
                color: primaryColor.withValues(alpha: 0.18),
                width: 1,
              ),
            ),
            padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  icon ?? Icons.lightbulb_outline,
                  color: primaryColor,
                  size: 22,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        title,
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(body, style: Theme.of(context).textTheme.bodySmall),
                      if (actionLabel != null && onAction != null) ...[
                        const SizedBox(height: 6),
                        GestureDetector(
                          onTap: () {
                            HapticFeedback.mediumImpact();
                            onAction!();
                            onDismiss();
                          },
                          child: Text(
                            actionLabel!,
                            style: Theme.of(context).textTheme.labelMedium
                                ?.copyWith(
                                  color: primaryColor,
                                  fontWeight: FontWeight.w700,
                                ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, size: 18),
                  onPressed: () {
                    HapticFeedback.lightImpact();
                    onDismiss();
                  },
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                    minWidth: 32,
                    minHeight: 32,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Presentation wrapper — registered on a [DiscoveryTip].
class BannerPresentation extends DiscoveryPresentation {
  final String title;
  final String body;
  final String? actionLabel;
  final void Function(DiscoveryContext ctx)? onAction;
  final IconData? icon;
  final Duration duration;
  final Color backgroundColor;
  final Color primaryColor;

  const BannerPresentation({
    required this.title,
    required this.body,
    required this.backgroundColor,
    required this.primaryColor,
    this.actionLabel,
    this.onAction,
    this.icon,
    this.duration = const Duration(seconds: 6),
  });

  @override
  Future<bool> present(
    BuildContext context,
    DiscoveryTip tip,
    DiscoveryContext ctx,
  ) async {
    OverlaySupportEntry? entry;
    entry = showOverlayNotification(
      (_) => DiscoveryBottomBanner(
        title: title,
        body: body,
        actionLabel: actionLabel,
        icon: icon,
        onAction: onAction == null ? null : () => onAction!(ctx),
        onDismiss: () => entry?.dismiss(),
        backgroundColor: backgroundColor,
        primaryColor: primaryColor,
      ),
      duration: duration,
      position: NotificationPosition.top,
    );
    return true;
  }
}
