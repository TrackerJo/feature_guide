# feature_guide

Feature-discovery toolkit for Flutter — tips, banners, coach marks, and "New" badges with session-aware gating and a persistent ledger.

- **Banners** — non-blocking top-anchored hints with an optional action.
- **Coach marks** — dimmed scrim with a cutout highlight and a bubble pointing at a target widget.
- **"New" badges** — little dot that auto-clears the first time the user touches a feature.
- **Modals & inline** — escape hatches for any other presentation you already have.
- **Session-aware gating** — only one non-critical tip per session-lock window; the lock clears on backgrounded-then-foregrounded app resume, or manually.
- **Priority chaining** — `critical` tips (permissions, data disclosures) can chain in a single emit.
- **Persistent ledger** — `SharedPreferences`-backed "seen / asked / counters" store.

## Install

```yaml
dependencies:
  feature_guide: ^0.1.0
```

```dart
import 'package:feature_guide/feature_guide.dart';
```

## Quick start

```dart
// 1. Define the event type your app emits. Any enum works.
enum AppEvent { onStartupTick, onProductViewed }

// 2. Initialize the ledger once, before running any emits.
await TipLedger().init();

// 3. Create a service bound to your event type and register tips.
final discovery = FeatureDiscoveryService<AppEvent>()
  ..register(
    DiscoveryTip<AppEvent>(
      id: 'welcome_banner',
      priority: DiscoveryPriority.standard,
      triggers: {AppEvent.onStartupTick},
      shouldShow: (ctx) async => ctx.appLaunches >= 2,
      presentation: BannerPresentation(
        title: 'Welcome back!',
        body: 'Tap the star to favorite a product.',
        cardColor: Colors.white,
        accentColor: Colors.indigo,
      ),
    ),
  );

// 4. Emit events from your widgets.
discovery.emit(
  context,
  AppEvent.onStartupTick,
  const DiscoveryContext(appLaunches: 2),
);
```

Don't forget to wrap your app in `OverlaySupport.global(child: MaterialApp(...))` — the banner uses `overlay_support` for its top-anchored entry.

## Concepts

### Events & triggers

Events are defined by the consumer as any `enum` (or any `Object` subtype). `FeatureDiscoveryService<E>` is typed on your event enum; a tip lists which events should evaluate it via its `triggers: {...}` set.

### Priorities

| Priority | Blocks on lock | Claims lock | Chains with rest of emit |
|----------|----------------|-------------|--------------------------|
| `critical` | no | no | yes |
| `standard` | no | yes | no |
| `optional` | no | yes | no |
| `tip` | yes | yes | no |

Use `critical` for permission prompts and data-disclosure notices; use `tip` for low-weight hints that should stand down if something else just showed.

### Session lock

When a non-critical tip fires, the service claims a session lock. Any `tip`-priority entry that would otherwise fire is suppressed until the lock clears. The lock clears automatically via [`onAppPaused`](#lifecycle-integration) / [`onAppResumed`](#lifecycle-integration) when the app stays backgrounded for at least `backgroundResetThreshold`, or manually via `discovery.resetSession()`.

### Ledger

`TipLedger` persists three things in one `SharedPreferences` key:
- `seen` — tip ids the user has seen (oneShot tips use this to self-suppress).
- `asked` — tip ids that prompted the user for something (e.g. a permission), regardless of answer.
- `counters` — named integer counters a tip's `shouldShow` can read via `ctx.read<int>('…')` if you pass them in through `DiscoveryContext.data`.

## Presentations

### `BannerPresentation`

Top-anchored banner, auto-dismisses after `duration`.

```dart
BannerPresentation(
  title: 'Streak saved',
  body: 'You hit your goal 3 days in a row.',
  cardColor: Colors.white,
  accentColor: Colors.amber.shade700,
  actionLabel: 'See stats',
  onAction: (ctx) => Navigator.pushNamed(context, '/stats'),
);
```

### `CoachMarkPresentation` + `DiscoveryAnchor`

Wrap the widget you want highlighted in a `DiscoveryAnchor` with a matching `anchorKey`. Register the anchor INSIDE the target (e.g. as the `icon:` of an `IconButton`) so the highlight hugs the visible content rather than the tap-padding box.

```dart
IconButton(
  onPressed: _save,
  icon: const DiscoveryAnchor(
    anchorKey: 'saveButton',
    child: Icon(Icons.bookmark_outline),
  ),
);

DiscoveryTip<AppEvent>(
  id: 'save_coach',
  priority: DiscoveryPriority.tip,
  triggers: {AppEvent.onProductViewed},
  shouldShow: (ctx) async => true,
  presentation: const CoachMarkPresentation(
    anchorKey: 'saveButton',
    title: 'Save for later',
    message: 'Tap the bookmark to keep this for your next visit.',
    bubbleColor: Colors.indigo,
    style: CoachMarkStyle.compact,
  ),
);
```

### `DiscoveryBadgeWrapper`

A small dot on the corner of a widget; clears when you call `TipLedger().markSeen(tipId)`.

```dart
DiscoveryBadgeWrapper(
  tipId: 'save_coach',
  dotColor: Colors.indigo,
  child: const Icon(Icons.bookmark_outline),
);
```

### `ModalPresentation`

Drop-in for `showDialog`.

```dart
ModalPresentation(
  build: (dialogCtx, ctx) => AlertDialog(
    title: const Text("What's new"),
    content: const Text('Dark mode is here.'),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(dialogCtx),
        child: const Text('Got it'),
      ),
    ],
  ),
);
```

### `InlinePresentation`

Call an existing `showX` function you already have.

```dart
InlinePresentation((context, ctx) async {
  await showMyCustomSheet(context);
  return true;
});
```

## Customization

- **Colors** — every widget accepts a required "primary" color (e.g. `bubbleColor`, `accentColor`, `dotColor`) plus optional overrides (`titleColor`, `messageColor`, `scrimColor`, `bubbleShadowColor`, …) with sensible defaults.
- **Storage key** — `TipLedger().init(storageKey: 'my_app_tips_v1')` to isolate state per flavor, per user, or from a previous package install.
- **Session reset window** — `FeatureDiscoveryService<E>(backgroundResetThreshold: Duration(seconds: 30))`.
- **Manual session reset** — `discovery.resetSession()` after an onboarding-complete event, or any other moment you want to re-open the tip queue.

## Lifecycle integration

Hook the service into your app's lifecycle so the session lock behaves the way users expect when they leave and return.

```dart
class _AppState extends State<MyApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.paused:
        discovery.onAppPaused();
        break;
      case AppLifecycleState.resumed:
        discovery.onAppResumed();
        break;
      default:
        break;
    }
  }
}
```

## Testing

`TipLedger` is a singleton, so tests should reset it between cases:

```dart
tearDown(() async {
  await TipLedger().resetForTests();
  FeatureDiscoveryService<AppEvent>().clear();
});
```

## Example

A runnable demo lives in [`example/`](./example). It registers a banner tip, a compact coach mark, and a badge, and shows the lifecycle hookup.
