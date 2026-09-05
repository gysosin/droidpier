import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_android_dex/ui/shell/app_shell.dart';
import 'package:open_android_dex/ui/theme/dex_theme.dart';
import 'package:open_dex_api/open_dex_api.dart';
import 'package:open_dex_core/open_dex_core.dart';

/// Opening the mirror is a request to the phone, not a local toggle: the
/// shell asks the facade to stream the screen when the frame opens and to
/// stop when it closes, by whichever door.
void main() {
  Future<_RecordingFacade> pumpShell(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(1280, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final _RecordingFacade facade = _RecordingFacade();
    addTearDown(facade.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: DexTheme.dark(),
        home: StreamBuilder<OpenDexSnapshot>(
          stream: facade.states,
          initialData: facade.snapshot,
          builder: (BuildContext context, AsyncSnapshot<OpenDexSnapshot> s) =>
              AppShell(
                snapshot: s.data!,
                facade: facade,
                now: DateTime.utc(2026, 9, 5, 10, 8),
              ),
        ),
      ),
    );
    for (int i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 120));
    }
    return facade;
  }

  Future<void> settle(WidgetTester tester) async {
    for (int i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 120));
    }
  }

  testWidgets('the header pill starts the mirror and stops it again', (
    WidgetTester tester,
  ) async {
    final _RecordingFacade facade = await pumpShell(tester);
    await tester.tap(find.text('Phone Mirror'));
    await settle(tester);
    expect(facade.calls, <String>['start']);
    // The preview has no phone; the frame says so instead of pretending.
    expect(find.text('The preview has no phone to mirror.'), findsOneWidget);

    await tester.tap(find.text('Phone Mirror'));
    await settle(tester);
    expect(facade.calls, <String>['start', 'stop']);
    expect(find.bySemanticsLabel('Phone mirror'), findsNothing);
  });

  testWidgets('the close dot on the frame stops the stream too', (
    WidgetTester tester,
  ) async {
    final _RecordingFacade facade = await pumpShell(tester);
    await tester.tap(find.text('Phone Mirror'));
    await settle(tester);
    await tester.tap(find.byTooltip('Hide the phone'));
    await settle(tester);
    expect(facade.calls, <String>['start', 'stop']);
  });
}

class _RecordingFacade extends MockOpenDexFacade {
  _RecordingFacade() : super(scenario: MockScenario.ready);

  final List<String> calls = <String>[];

  @override
  Future<VoidResult> startDisplayMirror() {
    calls.add('start');
    return super.startDisplayMirror();
  }

  @override
  Future<VoidResult> stopDisplayMirror() {
    calls.add('stop');
    return super.stopDisplayMirror();
  }
}
