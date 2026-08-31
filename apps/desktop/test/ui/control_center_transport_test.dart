import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_dex_api/open_dex_api.dart';
import 'package:open_android_dex/ui/desk/control_center.dart';
import 'package:open_android_dex/ui/theme/dex_theme.dart';

/// Transport safety in the control centre.
///
/// Turning Wi-Fi off on a phone that is attached *over* Wi-Fi cuts the link
/// carrying the command. The backend refuses it independently; this asserts the
/// UI half — the control is not offered, says why, and is still offered over
/// USB, where it is a perfectly ordinary thing to do.
void main() {
  const DeviceTelemetry telemetry = DeviceTelemetry(
    wifiEnabled: true,
    bluetoothEnabled: false,
    rotationLocked: false,
  );

  final List<String> toggles = <String>[];

  setUp(toggles.clear);

  Future<void> pump(WidgetTester tester, DeviceConnectionKind? kind) async {
    await tester.binding.setSurfaceSize(const Size(600, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        theme: DexTheme.dark(),
        home: Material(
          child: Center(
            child: ControlCenter(
              telemetry: telemetry,
              clipboard: const ClipboardState(),
              connectionKind: kind,
              onToggleControl: (DeviceControl c, bool enabled) =>
                  toggles.add('${c.name}=$enabled'),
              onToggleClipboardSync: (_) {},
              onSetVolume: (_, _) {},
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    for (int i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 120));
    }
  }

  /// The tile's own tap handler. Null means the control is inert — the check
  /// that matters, because a tile that merely ignores a tap still invites one.
  VoidCallback? tapHandler(WidgetTester tester, String label) {
    return tester
        .widget<InkWell>(
          find
              .ancestor(of: find.text(label), matching: find.byType(InkWell))
              .first,
        )
        .onTap;
  }

  testWidgets('Wi-Fi cannot be turned off over a Wi-Fi transport', (
    WidgetTester tester,
  ) async {
    final SemanticsHandle handle = tester.ensureSemantics();
    await pump(tester, DeviceConnectionKind.wifi);

    await tester.tap(find.text('Wi-Fi'), warnIfMissed: false);
    await tester.pump();
    expect(
      toggles,
      isEmpty,
      reason: 'pressing must not send a command that would cut the link',
    );

    expect(
      find.bySemanticsLabel(
        RegExp('Wi-Fi, unavailable: Wi-Fi must stay on for wireless debugging'),
      ),
      findsOneWidget,
    );
    expect(
      tapHandler(tester, 'Wi-Fi'),
      isNull,
      reason: 'a control that cannot be used must not accept a press',
    );
    handle.dispose();

    final Tooltip tip = tester.widget<Tooltip>(
      find
          .ancestor(of: find.text('Wi-Fi'), matching: find.byType(Tooltip))
          .first,
    );
    expect(tip.message, contains('Wi-Fi must stay on for wireless debugging'));
    expect(tip.message, contains('would cut the link'));
  });

  testWidgets('Wi-Fi stays usable over USB', (WidgetTester tester) async {
    final SemanticsHandle handle = tester.ensureSemantics();
    await pump(tester, DeviceConnectionKind.usb);

    await tester.tap(find.text('Wi-Fi'));
    await tester.pump();
    expect(toggles, <String>['wifi=false']);

    expect(find.bySemanticsLabel(RegExp('unavailable')), findsNothing);
    expect(tapHandler(tester, 'Wi-Fi'), isNotNull);
    handle.dispose();
  });

  testWidgets('with no phone selected the control is left alone', (
    WidgetTester tester,
  ) async {
    await pump(tester, null);
    await tester.tap(find.text('Wi-Fi'));
    await tester.pump();
    expect(toggles, <String>['wifi=false']);
  });

  testWidgets('the lock is specific to Wi-Fi, not to every control', (
    WidgetTester tester,
  ) async {
    await pump(tester, DeviceConnectionKind.wifi);

    await tester.tap(find.text('Bluetooth'));
    await tester.pump();
    expect(toggles, <String>['bluetooth=true']);

    // Torch was never reported by this phone: still unavailable, and for a
    // different reason than the transport lock.
    await tester.tap(find.text('Torch'), warnIfMissed: false);
    await tester.pump();
    expect(toggles, <String>['bluetooth=true']);
  });
}
