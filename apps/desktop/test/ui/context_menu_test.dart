import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_android_dex/ui/theme/dex_theme.dart';
import 'package:open_android_dex/ui/widgets/context_menu.dart';

/// The shared right-click menu.
///
/// One primitive serves both the app drawer's Pin/Unpin and the window title
/// bar's snap and close actions. It knows nothing about apps or windows: it
/// takes labelled actions and reports which was chosen.
void main() {
  Future<void> pumpMenu(
    WidgetTester tester,
    List<DexMenuAction> actions,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: DexTheme.dark(),
        home: Scaffold(
          body: Builder(
            builder: (BuildContext context) => Center(
              child: GestureDetector(
                onSecondaryTapDown: (TapDownDetails d) => showDexContextMenu(
                  context: context,
                  globalPosition: d.globalPosition,
                  actions: actions,
                ),
                child: const SizedBox(
                  width: 200,
                  height: 100,
                  child: ColoredBox(color: Colors.grey),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('right-click opens the menu with the given actions', (
    WidgetTester tester,
  ) async {
    await pumpMenu(tester, <DexMenuAction>[
      DexMenuAction(label: 'Pin', onSelected: () {}),
      DexMenuAction(label: 'Close others', onSelected: () {}),
    ]);

    expect(find.text('Pin'), findsNothing);
    await tester.tapAt(const Offset(400, 300), buttons: 2);
    await tester.pumpAndSettle();

    expect(find.text('Pin'), findsOneWidget);
    expect(find.text('Close others'), findsOneWidget);
  });

  testWidgets('choosing an item runs exactly that action', (
    WidgetTester tester,
  ) async {
    final List<String> chosen = <String>[];
    await pumpMenu(tester, <DexMenuAction>[
      DexMenuAction(label: 'Pin', onSelected: () => chosen.add('pin')),
      DexMenuAction(label: 'Unpin', onSelected: () => chosen.add('unpin')),
    ]);

    await tester.tapAt(const Offset(400, 300), buttons: 2);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Unpin'));
    await tester.pumpAndSettle();

    expect(chosen, <String>['unpin']);
  });

  testWidgets('a separator does not render as a choosable row', (
    WidgetTester tester,
  ) async {
    // Grouping snap actions apart from Close needs a rule, not a blank item
    // that can be clicked and does nothing.
    await pumpMenu(tester, <DexMenuAction>[
      DexMenuAction(label: 'Left half', onSelected: () {}),
      const DexMenuAction.separator(),
      DexMenuAction(label: 'Close', onSelected: () {}),
    ]);

    await tester.tapAt(const Offset(400, 300), buttons: 2);
    await tester.pumpAndSettle();

    expect(find.text('Left half'), findsOneWidget);
    expect(find.text('Close'), findsOneWidget);
    expect(find.byType(Divider), findsOneWidget);
  });

  testWidgets('dismissing without choosing runs nothing', (
    WidgetTester tester,
  ) async {
    final List<String> chosen = <String>[];
    await pumpMenu(tester, <DexMenuAction>[
      DexMenuAction(label: 'Pin', onSelected: () => chosen.add('pin')),
    ]);

    await tester.tapAt(const Offset(400, 300), buttons: 2);
    await tester.pumpAndSettle();
    // Tapping the barrier is how a person changes their mind.
    await tester.tapAt(const Offset(20, 20));
    await tester.pumpAndSettle();

    expect(chosen, isEmpty);
    expect(find.text('Pin'), findsNothing);
  });
}
