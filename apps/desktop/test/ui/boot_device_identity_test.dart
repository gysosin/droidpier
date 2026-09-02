import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_dex_api/open_dex_api.dart';
import 'package:open_android_dex/ui/boot/boot_screen.dart';
import 'package:open_android_dex/ui/theme/dex_theme.dart';

/// Which phone the desk is coming up on.
///
/// The boot screen was handed the boot state and nothing else, so it could not
/// name the phone even in principle. With one device that is merely incurious;
/// with two it means the app connects to one of them and never says which, and
/// the person has no way to tell which phone they are about to be looking at.
void main() {
  DeviceSummary device({
    String name = 'Pixel 7a',
    DeviceConnectionKind kind = DeviceConnectionKind.wifi,
  }) => DeviceSummary(
    id: 'serial-1',
    name: name,
    connectionKind: kind,
    status: DeviceStatus.authorized,
    androidVersion: '14',
  );

  Future<void> pump(
    WidgetTester tester, {
    required BootPhase phase,
    DeviceSummary? selected,
    int deviceCount = 0,
  }) async {
    await tester.binding.setSurfaceSize(const Size(1280, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        theme: DexTheme.dark(),
        home: BootScreen(
          boot: BootState(phase: phase, message: 'Working'),
          onConnect: () {},
          onRetry: () {},
          device: selected,
          deviceCount: deviceCount,
        ),
      ),
    );
    await tester.pump();
    for (int i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 120));
    }
  }

  testWidgets('the phone being connected to is named', (
    WidgetTester tester,
  ) async {
    await pump(
      tester,
      phase: BootPhase.awaitingHandshakes,
      selected: device(),
      deviceCount: 1,
    );
    expect(find.textContaining('Pixel 7a'), findsOneWidget);
  });

  testWidgets('how it is attached is named too', (WidgetTester tester) async {
    // Two phones of the same model are told apart by the cable, not the name.
    await pump(
      tester,
      phase: BootPhase.awaitingHandshakes,
      selected: device(kind: DeviceConnectionKind.usb),
      deviceCount: 2,
    );
    expect(find.textContaining('USB'), findsOneWidget);
  });

  testWidgets('with more than one attached, another can be chosen', (
    WidgetTester tester,
  ) async {
    // Not only after a failure. The complaint is not being able to tell which
    // phone was picked, and by the time it has failed the choice is moot.
    await pump(
      tester,
      phase: BootPhase.awaitingHandshakes,
      selected: device(),
      deviceCount: 2,
    );
    expect(find.text('Choose a phone'), findsOneWidget);
  });

  testWidgets('with only one attached there is nothing to choose between', (
    WidgetTester tester,
  ) async {
    await pump(
      tester,
      phase: BootPhase.awaitingHandshakes,
      selected: device(),
      deviceCount: 1,
    );
    expect(find.text('Choose a phone'), findsNothing);
  });

  testWidgets('no phone yet means no claim about one', (
    WidgetTester tester,
  ) async {
    await pump(tester, phase: BootPhase.idle);
    expect(find.textContaining('Pixel'), findsNothing);
    expect(find.textContaining('USB'), findsNothing);
  });
}
