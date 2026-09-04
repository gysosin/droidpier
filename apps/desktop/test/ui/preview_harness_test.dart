import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_android_dex/ui/preview/preview_app.dart';

/// Every surface in the harness must actually render.
///
/// The harness offered six of roughly eighteen surfaces, which is how a screen
/// gets built, tested, and then quietly left unreachable — this repository has
/// done it four times. A switcher entry that throws when selected is the same
/// failure wearing a chip, so this walks all of them.
void main() {
  testWidgets('every preview surface renders', (WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(1440, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(const PreviewApp());
    for (int i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 120));
    }

    final int surfaces = tester.widgetList(find.byType(ChoiceChip)).length;
    expect(
      surfaces,
      greaterThanOrEqualTo(17),
      reason: 'the harness must offer every surface, not a chosen few',
    );

    for (int i = 0; i < surfaces; i++) {
      await tester.tap(find.byType(ChoiceChip).at(i), warnIfMissed: false);
      for (int p = 0; p < 4; p++) {
        await tester.pump(const Duration(milliseconds: 120));
      }
      expect(
        tester.takeException(),
        isNull,
        reason: 'surface $i threw when selected',
      );
    }
  });
}
