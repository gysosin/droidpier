import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_android_dex/ui/diagnostics/stream_diagnostics.dart';
import 'package:open_android_dex/ui/shell/app_shell.dart';
import 'package:open_android_dex/ui/theme/dex_colors.dart';
import 'package:open_android_dex/ui/theme/dex_theme.dart';
import 'package:open_dex_api/open_dex_api.dart';
import 'package:open_dex_core/open_dex_core.dart';

/// Two reported faults here were the product working. The chrome now says
/// less, so the numbers have to be reachable somewhere — a keypress, not a
/// support conversation.
void main() {
  _rateTests();
  Future<MockOpenDexFacade> pumpShell(WidgetTester tester) async {
    final MockOpenDexFacade facade = MockOpenDexFacade(
      scenario: MockScenario.ready,
    );
    addTearDown(facade.dispose);
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        theme: DexTheme.dark(),
        home: StreamBuilder<OpenDexSnapshot>(
          stream: facade.states,
          initialData: facade.snapshot,
          builder: (BuildContext context, AsyncSnapshot<OpenDexSnapshot> s) =>
              AppShell(
                snapshot: s.data ?? facade.snapshot,
                facade: facade,
                now: DateTime.utc(2026, 8, 25, 14, 30),
              ),
        ),
      ),
    );
    for (int i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 120));
    }
    return facade;
  }

  Future<void> pressToggle(WidgetTester tester) async {
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyD);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
    for (int i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 120));
    }
  }

  testWidgets('Ctrl+Shift+D opens and closes the stream diagnostics', (
    WidgetTester tester,
  ) async {
    await pumpShell(tester);
    expect(find.byType(StreamDiagnostics), findsNothing);

    await pressToggle(tester);
    expect(find.byType(StreamDiagnostics), findsOneWidget);

    await pressToggle(tester);
    expect(find.byType(StreamDiagnostics), findsNothing);
  });

  testWidgets('Escape closes it', (WidgetTester tester) async {
    await pumpShell(tester);
    await pressToggle(tester);
    expect(find.byType(StreamDiagnostics), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(find.byType(StreamDiagnostics), findsNothing);
  });

  testWidgets('with no windows it says so rather than showing an empty box', (
    WidgetTester tester,
  ) async {
    await pumpShell(tester);
    await pressToggle(tester);
    expect(find.text('No app windows are open.'), findsOneWidget);
  });

  testWidgets('a live window reports its size and update rate', (
    WidgetTester tester,
  ) async {
    // Built directly rather than through the mock: the mock publishes fps as
    // device telemetry, not per window, so a mock-launched window has none —
    // and a row that omits a number it does not have is correct behaviour, not
    // something to assert around.
    tester.view.physicalSize = const Size(900, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        theme: DexTheme.dark(),
        home: Scaffold(
          body: StreamDiagnostics(
            snapshot: const OpenDexSnapshot(
              windows: <WindowSessionState>[
                WindowSessionState(
                  id: 'w',
                  application: AndroidApplication(
                    packageName: 'com.google.android.youtube',
                    label: 'YouTube',
                  ),
                  status: WindowSessionStatus.streaming,
                  displayId: 254,
                  isFocused: true,
                  producedFramesPerSecond: 71.9,
                  presentedFramesPerSecond: 14.8,
                  droppedFramesPerSecond: 57.1,
                  surface: WindowSurface(
                    textureId: 1,
                    pixelSize: WindowPixelSize(width: 1280, height: 720),
                  ),
                ),
              ],
            ),
            recentExits: const <String>['2:14  Airtel — stopped unexpectedly'],
            onClose: () {},
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.textContaining('1280x720'), findsOneWidget);
    expect(
      find.textContaining('15/s on screen'),
      findsOneWidget,
      reason: 'the number must carry its meaning wherever it is shown',
    );
    expect(find.textContaining('display 254'), findsOneWidget);
    expect(find.text('live'), findsOneWidget);
    expect(
      find.textContaining('Airtel — stopped unexpectedly'),
      findsOneWidget,
      reason: 'a window that vanished is exactly what this is for',
    );
  });

  testWidgets('the panel never blurs — it is opened over live video', (
    WidgetTester tester,
  ) async {
    await pumpShell(tester);
    await pressToggle(tester);
    final Finder panelBlur = find.descendant(
      of: find.byType(StreamDiagnostics),
      matching: find.byType(BackdropFilter),
    );
    expect(
      panelBlur,
      findsNothing,
      reason: 'a blur here would re-run on every decoded frame beneath it',
    );
  });
}

void _rateTests() {
  Widget panel(WindowSessionState window) => MaterialApp(
    theme: DexTheme.dark(),
    home: Scaffold(
      body: StreamDiagnostics(
        snapshot: OpenDexSnapshot(windows: <WindowSessionState>[window]),
        recentExits: const <String>[],
        onClose: () {},
      ),
    ),
  );

  const AndroidApplication app = AndroidApplication(
    packageName: 'com.example.probe',
    label: 'Probe',
  );

  testWidgets('all three rates are shown, so the gap is readable', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(900, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      panel(
        const WindowSessionState(
          id: 'w',
          application: app,
          status: WindowSessionStatus.streaming,
          producedFramesPerSecond: 71.9,
          presentedFramesPerSecond: 14.8,
          droppedFramesPerSecond: 57.1,
        ),
      ),
    );

    // The number a person actually lives in comes first; the misleading one is
    // still shown, but it is not the headline and it is not alone.
    expect(find.textContaining('15/s on screen'), findsOneWidget);
    expect(find.textContaining('72/s produced'), findsOneWidget);
    expect(find.textContaining('57/s dropped'), findsOneWidget);
  });

  testWidgets('a rate is never shown without saying which one it is', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(900, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      panel(
        const WindowSessionState(
          id: 'w',
          application: app,
          status: WindowSessionStatus.streaming,
          // Only one rate known. The legacy gateway populated a single
          // ambiguous field and both gateways disagreed about its meaning;
          // whatever we render must still name the quantity.
          presentedFramesPerSecond: 30,
        ),
      ),
    );

    expect(find.textContaining('30/s on screen'), findsOneWidget);
    expect(find.textContaining('produced'), findsNothing);
  });

  testWidgets('a pipeline losing most of its frames is not styled calmly', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(900, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      panel(
        const WindowSessionState(
          id: 'w',
          application: app,
          status: WindowSessionStatus.streaming,
          producedFramesPerSecond: 71.9,
          presentedFramesPerSecond: 14.8,
          droppedFramesPerSecond: 57.1,
        ),
      ),
    );

    final DexColors colors = DexTheme.dark().extension<DexColors>()!;
    final Text rates = tester.widget<Text>(
      find.byWidgetPredicate(
        (Widget w) =>
            w is Text &&
            (w.textSpan?.toPlainText() ?? '').contains('on screen'),
      ),
    );
    final List<InlineSpan> spans =
        (rates.textSpan! as TextSpan).children!.cast<InlineSpan>();
    final TextSpan onScreen = spans.first as TextSpan;
    expect(onScreen.style?.color, colors.fault);
  });

  testWidgets('an ordinary drop rate stays in the normal colour', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(900, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      panel(
        const WindowSessionState(
          id: 'w',
          application: app,
          status: WindowSessionStatus.streaming,
          producedFramesPerSecond: 60,
          presentedFramesPerSecond: 59,
          droppedFramesPerSecond: 1,
        ),
      ),
    );

    final DexColors colors = DexTheme.dark().extension<DexColors>()!;
    final Text rates = tester.widget<Text>(
      find.byWidgetPredicate(
        (Widget w) =>
            w is Text &&
            (w.textSpan?.toPlainText() ?? '').contains('on screen'),
      ),
    );
    final List<InlineSpan> spans =
        (rates.textSpan! as TextSpan).children!.cast<InlineSpan>();
    final TextSpan onScreen = spans.first as TextSpan;
    expect(onScreen.style?.color, colors.text);
  });
}
