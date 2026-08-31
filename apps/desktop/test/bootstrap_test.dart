import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_android_dex/bootstrap/reporting_facade.dart';
import 'package:open_android_dex/main.dart';
import 'package:open_dex_api/open_dex_api.dart';
import 'package:open_dex_core/open_dex_core.dart';

void main() {
  testWidgets('bootstrap injects the facade and auto-connects one phone', (
    tester,
  ) async {
    final facade = MockOpenDexFacade(scenario: MockScenario.disconnected);

    await tester.pumpWidget(OpenDexApplication(facade: facade));
    await tester.pump(const Duration(seconds: 1));

    expect(find.byTooltip('Your apps'), findsOneWidget);
    expect(find.text('Connect phone'), findsNothing);
    expect(facade.snapshot.boot.phase, BootPhase.ready);

    // Let the connected desk's bounded entrance stagger finish, then dispose
    // its production clock before the test binding checks for pending timers.
    for (var step = 0; step < 10; step++) {
      await tester.pump(const Duration(milliseconds: 120));
    }
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });

  test('reporting facade publishes typed command failures', () async {
    final errors = <OpenDexError>[];
    final facade = ReportingOpenDexFacade(
      delegate: MockOpenDexFacade(scenario: MockScenario.ready),
      onError: errors.add,
    );
    addTearDown(facade.dispose);

    final result = await facade.focusWindow('missing-window');

    expect(result, isA<CommandFailure<void>>());
    expect(errors, hasLength(1));
    expect(errors.single.message, 'That application window has closed.');
  });
}
