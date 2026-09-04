import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_dex_api/open_dex_api.dart';
import 'package:open_dex_core/open_dex_core.dart';
import 'package:open_android_dex/bootstrap/reporting_facade.dart';
import 'package:open_android_dex/ui/shell/app_shell.dart';
import 'package:open_android_dex/ui/theme/dex_theme.dart';

/// The desk search must reach the browser through the facade.
///
/// It used to call `Process.start('xdg-open', …)` straight from `lib/ui`, which
/// is the one thing the layering rule forbids: a widget that talks to the host
/// directly cannot be rendered in the preview harness, and cannot be covered by
/// a test without actually launching a browser.
void main() {
  testWidgets('submitting the desk search opens a URL through the facade', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1280, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final MockOpenDexFacade backing = MockOpenDexFacade(
      scenario: MockScenario.ready,
    );
    addTearDown(backing.dispose);
    final _RecordingFacade facade = _RecordingFacade(backing);

    await tester.pumpWidget(
      MaterialApp(
        theme: DexTheme.dark(),
        home: AppShell(
          snapshot: facade.snapshot,
          facade: facade,
          now: DateTime.utc(2026, 8, 24, 22),
        ),
      ),
    );
    await tester.pump();
    for (int i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 120));
    }

    // The desk carries exactly one field when nothing is open over it.
    final Finder field = find.byType(TextField);
    expect(field, findsOneWidget);

    await tester.enterText(field, 'link rail');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pump();

    expect(facade.openedUrls, <String>[
      'https://www.google.com/search?q=link+rail',
    ]);
  });
}

/// Records what the desk asked the host to open.
///
/// Extends the bootstrap's reporting wrapper rather than reimplementing 37
/// delegating methods, so it keeps working as the facade grows.
class _RecordingFacade extends ReportingOpenDexFacade {
  _RecordingFacade(OpenDexFacade delegate)
    : super(delegate: delegate, onError: _ignoreError);

  static void _ignoreError(OpenDexError error) {}

  final List<String> openedUrls = <String>[];

  @override
  Future<VoidResult> openUrl(String url) {
    openedUrls.add(url);
    return super.openUrl(url);
  }
}
