import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_dex_api/open_dex_api.dart';
import 'package:open_android_dex/ui/apps/app_drawer.dart';
import 'package:open_android_dex/ui/theme/dex_theme.dart';

/// Drawer search, driven from the keyboard.
///
/// The ranking itself is covered as pure functions in app_ranking_test.dart;
/// what matters here is that a person can drive the results without reaching
/// for the mouse, and can see where Enter will go.
void main() {
  const List<AndroidApplication> apps = <AndroidApplication>[
    AndroidApplication(packageName: 'com.whatsapp', label: 'WhatsApp'),
    AndroidApplication(
      packageName: 'com.example.softwareupdate',
      label: 'Software Update',
      isSystemApp: true,
    ),
    AndroidApplication(packageName: 'com.example.wallet', label: 'Wallet'),
  ];

  Future<void> pumpDrawer(
    WidgetTester tester, {
    required List<String> launched,
  }) async {
    await tester.binding.setSurfaceSize(const Size(1280, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        theme: DexTheme.dark(),
        // The drawer normally renders inside the shell's Material; on its own
        // its TextField has no Material ancestor to ink onto.
        home: Scaffold(
          body: AppDrawer(
            status: LoadStatus.ready,
            applications: apps,
            onLaunch: launched.add,
            onRefresh: () {},
            onDismiss: () {},
          ),
        ),
      ),
    );
    await tester.pump();
    for (int i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 120));
    }
  }

  testWidgets('Enter opens the top ranked result', (WidgetTester tester) async {
    final List<String> launched = <String>[];
    await pumpDrawer(tester, launched: launched);

    await tester.enterText(find.byType(TextField), 'wa');
    await tester.pump();
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();

    // Wallet, not WhatsApp: "wa" literally starts Wallet, while WhatsApp only
    // matches on its initials. A literal prefix is the stronger signal and
    // outranks an acronym deliberately.
    expect(launched, <String>['com.example.wallet']);
  });

  testWidgets('arrow down moves the selection before Enter', (
    WidgetTester tester,
  ) async {
    final List<String> launched = <String>[];
    await pumpDrawer(tester, launched: launched);

    await tester.enterText(find.byType(TextField), 'wa');
    await tester.pump();
    for (int i = 0; i < 3; i++) {
      await tester.pump(const Duration(milliseconds: 120));
    }

    // The selection marker rides the selected row, so exactly one exists.
    expect(find.text('Enter'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();

    expect(launched, hasLength(1));
    expect(
      launched.single,
      isNot('com.example.wallet'),
      reason: 'arrow down should have moved off the top result',
    );
  });

  testWidgets('the selection wraps rather than sticking at the end', (
    WidgetTester tester,
  ) async {
    final List<String> launched = <String>[];
    await pumpDrawer(tester, launched: launched);

    await tester.enterText(find.byType(TextField), 'wa');
    await tester.pump();
    for (int i = 0; i < 3; i++) {
      await tester.pump(const Duration(milliseconds: 120));
    }

    // Up from the top wraps to the bottom — a list you cannot leave from
    // either end is a trap in miniature.
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pump();
    expect(find.text('Enter'), findsOneWidget);
  });

  testWidgets('typing resets the selection to the top', (
    WidgetTester tester,
  ) async {
    final List<String> launched = <String>[];
    await pumpDrawer(tester, launched: launched);

    await tester.enterText(find.byType(TextField), 'wa');
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();

    // A new query means new results; keeping the old index would land Enter on
    // something the person never looked at.
    await tester.enterText(find.byType(TextField), 'what');
    await tester.pump();
    for (int i = 0; i < 3; i++) {
      await tester.pump(const Duration(milliseconds: 120));
    }
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();

    expect(
      launched,
      <String>['com.whatsapp'],
      reason: '"what" is a literal prefix of WhatsApp and nothing else',
    );
  });

  testWidgets('an empty query still shows the browsing grid', (
    WidgetTester tester,
  ) async {
    await pumpDrawer(tester, launched: <String>[]);
    // The section header renders uppercased.
    expect(find.text('USER APPS'), findsOneWidget);
    expect(find.text('Enter'), findsNothing);
  });
}
