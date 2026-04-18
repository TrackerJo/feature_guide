import 'package:feature_guide/feature_guide.dart';
import 'package:flutter/material.dart';
import 'package:overlay_support/overlay_support.dart';

/// Events this demo emits. `FeatureDiscoveryService` is generic on this enum.
enum DemoEvent { onStartupTick, onProductViewed }

late final FeatureDiscoveryService<DemoEvent> discovery;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await TipLedger().init();

  discovery = FeatureDiscoveryService<DemoEvent>()
    ..registerAll([
      DiscoveryTip<DemoEvent>(
        id: 'welcome_banner',
        priority: DiscoveryPriority.standard,
        triggers: {DemoEvent.onStartupTick},
        shouldShow: (ctx) async => true,
        presentation: BannerPresentation(
          title: 'Welcome!',
          body: 'Try tapping the bookmark to see a coach mark.',
          cardColor: Colors.white,
          accentColor: Colors.indigo,
        ),
      ),
      DiscoveryTip<DemoEvent>(
        id: 'bookmark_coach',
        // `standard` (not `tip`) so the welcome banner's session lock doesn't
        // suppress this coach mark when the user taps "View product".
        priority: DiscoveryPriority.standard,
        triggers: {DemoEvent.onProductViewed},
        shouldShow: (ctx) async => true,
        presentation: const CoachMarkPresentation(
          anchorKey: 'bookmarkBtn',
          title: 'Save for later',
          message: 'Tap the bookmark to keep this product for your next visit.',
          bubbleColor: Colors.indigo,
          style: CoachMarkStyle.compact,
        ),
      ),
    ]);

  runApp(const _App());
}

class _App extends StatefulWidget {
  const _App();

  @override
  State<_App> createState() => _AppState();
}

class _AppState extends State<_App> with WidgetsBindingObserver {
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

  @override
  Widget build(BuildContext context) {
    return OverlaySupport.global(
      child: MaterialApp(
        title: 'feature_guide demo',
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
          useMaterial3: true,
        ),
        home: const _HomeScreen(),
      ),
    );
  }
}

class _HomeScreen extends StatefulWidget {
  const _HomeScreen();

  @override
  State<_HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<_HomeScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      discovery.emit(
        context,
        DemoEvent.onStartupTick,
        const DiscoveryContext(appLaunches: 1),
      );
    });
  }

  void _openProduct() {
    discovery.emit(
      context,
      DemoEvent.onProductViewed,
      const DiscoveryContext(),
    );
  }

  Future<void> _clearSeenTips() async {
    // `clearSeen` is the public API for undoing a "seen" mark. For full state
    // reset in a test, use `TipLedger().resetForTests()` (test-only).
    await TipLedger().clearSeen('welcome_banner');
    await TipLedger().clearSeen('bookmark_coach');
    await TipLedger().clearSeen('reset_badge');
    discovery.resetSession();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Seen state cleared — restart to see tips again.'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('feature_guide'),
        actions: [
          // Wrapping the action icon in a DiscoveryBadgeWrapper puts a small
          // "New" dot in its corner until markSeen fires.
          DiscoveryBadgeWrapper(
            tipId: 'reset_badge',
            dotColor: Colors.redAccent,
            child: IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: () async {
                await TipLedger().markSeen('reset_badge');
                await _clearSeenTips();
              },
            ),
          ),
        ],
      ),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            FilledButton(
              onPressed: _openProduct,
              child: const Text('View product'),
            ),
            const SizedBox(height: 24),
            // DiscoveryAnchor registers against anchorKey 'bookmarkBtn' so the
            // coach-mark in main() can find this widget.
            IconButton(
              onPressed: _openProduct,
              icon: const DiscoveryAnchor(
                anchorKey: 'bookmarkBtn',
                child: Icon(Icons.bookmark_outline, size: 32),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
