## 0.1.1

- Added `DiscoveryBadgeWrapper` to example app

## 0.1.0

- Initial release.
- `FeatureDiscoveryService<E>` — generic tip orchestrator parameterized on the consumer's event enum, with priority, session lock, and critical-tip chaining.
- `TipLedger` — persistent "seen / asked / counters" store backed by `SharedPreferences` with a configurable storage key.
- Presentations: `BannerPresentation`, `CoachMarkPresentation` (classic + compact styles), `DiscoveryBadgeWrapper`, `ModalPresentation`, `InlinePresentation`.
- `DiscoveryAnchor` — self-registering anchor for coach marks, no `GlobalKey` plumbing.
