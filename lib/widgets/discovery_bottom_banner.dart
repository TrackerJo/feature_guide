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

  /// Fill color of the banner card.
  final Color cardColor;

  /// Accent color — drives the leading icon, action label, and (by default)
  /// the border tint. Override the specific overrides below to break the tie.
  final Color accentColor;

  /// Color of the leading icon. Defaults to [accentColor].
  final Color? iconColor;

  /// Color of the action label text. Defaults to [accentColor].
  final Color? actionLabelColor;

  /// Border color around the card. Defaults to [accentColor] at 18% opacity.
  final Color? borderColor;

  /// Color of the title text. Defaults to the theme's titleSmall color.
  final Color? titleColor;

  /// Color of the body text. Defaults to the theme's bodySmall color.
  final Color? bodyColor;

  /// Color of the trailing close (✕) icon. Defaults to the theme's icon color.
  final Color? closeIconColor;

  /// Drop-shadow color behind the card.
  final Color shadowColor;

  const DiscoveryBottomBanner({
    super.key,
    required this.title,
    required this.body,
    required this.onDismiss,
    required this.cardColor,
    required this.accentColor,
    this.actionLabel,
    this.onAction,
    this.icon,
    this.iconColor,
    this.actionLabelColor,
    this.borderColor,
    this.titleColor,
    this.bodyColor,
    this.closeIconColor,
    this.shadowColor = const Color(0x2E000000),
  });

  @override
  Widget build(BuildContext context) {
    final resolvedBorderColor =
        borderColor ?? accentColor.withValues(alpha: 0.18);
    final resolvedIconColor = iconColor ?? accentColor;
    final resolvedActionColor = actionLabelColor ?? accentColor;
    return SafeArea(
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
        child: Material(
          color: Colors.transparent,
          child: Container(
            decoration: BoxDecoration(
              color: cardColor,
              borderRadius: BorderRadius.circular(14),
              boxShadow: [
                BoxShadow(
                  color: shadowColor,
                  blurRadius: 16,
                  offset: const Offset(0, 4),
                ),
              ],
              border: Border.all(color: resolvedBorderColor, width: 1),
            ),
            padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  icon ?? Icons.lightbulb_outline,
                  color: resolvedIconColor,
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
                          color: titleColor,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        body,
                        style: Theme.of(
                          context,
                        ).textTheme.bodySmall?.copyWith(color: bodyColor),
                      ),
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
                                  color: resolvedActionColor,
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
                  color: closeIconColor,
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

  /// See [DiscoveryBottomBanner.cardColor].
  final Color cardColor;

  /// See [DiscoveryBottomBanner.accentColor].
  final Color accentColor;

  final Color? iconColor;
  final Color? actionLabelColor;
  final Color? borderColor;
  final Color? titleColor;
  final Color? bodyColor;
  final Color? closeIconColor;
  final Color shadowColor;

  const BannerPresentation({
    required this.title,
    required this.body,
    required this.cardColor,
    required this.accentColor,
    this.actionLabel,
    this.onAction,
    this.icon,
    this.iconColor,
    this.actionLabelColor,
    this.borderColor,
    this.titleColor,
    this.bodyColor,
    this.closeIconColor,
    this.shadowColor = const Color(0x2E000000),
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
        cardColor: cardColor,
        accentColor: accentColor,
        iconColor: iconColor,
        actionLabelColor: actionLabelColor,
        borderColor: borderColor,
        titleColor: titleColor,
        bodyColor: bodyColor,
        closeIconColor: closeIconColor,
        shadowColor: shadowColor,
      ),
      duration: duration,
      position: NotificationPosition.top,
    );
    return true;
  }
}
