import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_dex_api/open_dex_api.dart';
import 'package:open_dex_core/open_dex_core.dart';
import 'package:open_android_dex/ui/desk/taskbar_bar.dart';
import 'package:open_android_dex/ui/shell/app_shell.dart';
import 'package:open_android_dex/ui/theme/dex_theme.dart';
import 'package:open_android_dex/ui/workspace/app_window.dart';

/// F11 puts the focused streaming window edge-to-edge with no desk chrome, and
/// Escape brings the desk back.
void main() {
  testWidgets('F11 enters edge-to-edge fullscreen; Escape leaves it', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1280, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final MockOpenDexFacade facade = MockOpenDexFacade(
      scenario: MockScenario.ready,
      attachSurfaces: true,
    );
    addTearDown(facade.dispose);

    await tester.pumpWidget(
      MaterialApp(
        theme: DexTheme.dark(),
        home: StreamBuilder<OpenDexSnapshot>(
          stream: facade.states,
          initialData: facade.snapshot,
          builder: (BuildContext context, AsyncSnapshot<OpenDexSnapshot> snap) =>
              AppShell(
                snapshot: snap.data!,
                facade: facade,
                now: DateTime.utc(2026, 8, 26, 22),
              ),
        ),
      ),
    );
    await tester.pump();

    await facade.launchApplication('com.google.android.youtube');
    for (int i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 120));
    }

    // Nothing is fullscreen yet.
    expect(find.byType(WindowStage), findsNothing);

    await simulateKeyDownEvent(LogicalKeyboardKey.f11);
    for (int i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 60));
    }

    // Edge-to-edge: the chromeless stage is up, painted over the whole desk.
    expect(find.byType(WindowStage), findsOneWidget);
    final Rect stage = tester.getRect(find.byType(WindowStage));
    expect(stage.width, 1280);
    expect(stage.height, 800);

    await simulateKeyDownEvent(LogicalKeyboardKey.escape);
    for (int i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 60));
    }

    // Back to the desk.
    expect(find.byType(WindowStage), findsNothing);
    expect(find.byType(TaskbarBar), findsOneWidget);
  });
}
