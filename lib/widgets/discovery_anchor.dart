import 'package:flutter/material.dart';

/// Wraps a widget so a coach mark can be anchored to it by string id.
///
/// The wrapper sizes exactly to its child, so the coach mark arrow hugs the
/// visible content — no `IconButton` tap-padding offset. Register the anchor
/// INSIDE the target (e.g. pass it as the `icon:` of an `IconButton`), not
/// around the whole tap target.
///
/// Example:
/// ```dart
/// IconButton(
///   onPressed: _log,
///   icon: DiscoveryAnchor(
///     anchorKey: 'logIcon',
///     child: Icon(Icons.edit_note, size: 28),
///   ),
/// );
/// ```
class DiscoveryAnchor extends StatefulWidget {
  /// Identifier matched by `CoachMarkPresentation.anchorKey`.
  final String anchorKey;
  final Widget child;

  const DiscoveryAnchor({
    super.key,
    required this.anchorKey,
    required this.child,
  });

  @override
  State<DiscoveryAnchor> createState() => _DiscoveryAnchorState();
}

class _DiscoveryAnchorState extends State<DiscoveryAnchor> {
  final GlobalKey _boxKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    DiscoveryAnchorRegistry.instance._register(widget.anchorKey, this);
  }

  @override
  void didUpdateWidget(covariant DiscoveryAnchor old) {
    super.didUpdateWidget(old);
    if (old.anchorKey != widget.anchorKey) {
      DiscoveryAnchorRegistry.instance._unregister(old.anchorKey, this);
      DiscoveryAnchorRegistry.instance._register(widget.anchorKey, this);
    }
  }

  @override
  void dispose() {
    DiscoveryAnchorRegistry.instance._unregister(widget.anchorKey, this);
    super.dispose();
  }

  Rect? currentRect() {
    final box = _boxKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return null;
    final offset = box.localToGlobal(Offset.zero);
    return Rect.fromLTWH(
      offset.dx,
      offset.dy,
      box.size.width,
      box.size.height,
    );
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(key: _boxKey, child: widget.child);
  }
}

/// Process-wide registry of mounted [DiscoveryAnchor]s keyed by anchor id.
///
/// Anchors register on `initState` and unregister on `dispose`, so a stale
/// key never resolves. If two screens happen to share an anchor id (e.g. the
/// same tip runs from either of two stacked routes), the most-recently
/// mounted onscreen anchor wins.
class DiscoveryAnchorRegistry {
  DiscoveryAnchorRegistry._();
  static final DiscoveryAnchorRegistry instance = DiscoveryAnchorRegistry._();

  final Map<String, List<_DiscoveryAnchorState>> _anchors = {};

  void _register(String key, _DiscoveryAnchorState state) {
    _anchors.putIfAbsent(key, () => []).add(state);
  }

  void _unregister(String key, _DiscoveryAnchorState state) {
    final list = _anchors[key];
    if (list == null) return;
    list.remove(state);
    if (list.isEmpty) _anchors.remove(key);
  }

  /// Current rect of the most-recently-registered anchor for [key], or null
  /// if none exists or none have a mounted render box yet.
  Rect? rectFor(String key) {
    final list = _anchors[key];
    if (list == null || list.isEmpty) return null;
    for (final state in list.reversed) {
      final rect = state.currentRect();
      if (rect != null) return rect;
    }
    return null;
  }
}
