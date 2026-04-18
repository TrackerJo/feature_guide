import 'package:feature_guide/feature_guide.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum _TestEvent { onStartup }

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await TipLedger().resetForTests();
  });

  testWidgets('tip fires once, then is suppressed by the ledger', (
    tester,
  ) async {
    await TipLedger().init();
    final service = FeatureDiscoveryService<_TestEvent>();
    addTearDown(service.clear);

    int presented = 0;
    service.register(
      DiscoveryTip<_TestEvent>(
        id: 'smoke',
        priority: DiscoveryPriority.standard,
        triggers: {_TestEvent.onStartup},
        shouldShow: (_) async => true,
        presentation: InlinePresentation((_, _) async {
          presented++;
          return true;
        }),
      ),
    );

    await tester.pumpWidget(const _Host());
    final context = tester.element(find.byType(_Host));

    await service.emit(context, _TestEvent.onStartup, const DiscoveryContext());
    await service.emit(context, _TestEvent.onStartup, const DiscoveryContext());

    expect(presented, 1);
    expect(TipLedger().hasSeen('smoke'), true);
  });
}

class _Host extends StatelessWidget {
  const _Host();

  @override
  Widget build(BuildContext context) => const SizedBox();
}
