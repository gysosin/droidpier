import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:open_dex_api/open_dex_api.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_android_dex/ui/workspace/window_input.dart';

/// The seam that defers M8's open question: does the backend want raw pointer
/// events from the UI, or does the embedded surface consume them itself?
///
/// Both strategies are exercised so whichever answer comes back is already
/// covered, rather than the wrong one being discovered late.
void main() {
  group('pointer mapping', _mappingTests);
  group('key mapping', _keyMappingTests);

  testWidgets('the surface strategy passes the child straight through', (
    WidgetTester tester,
  ) async {
    const WindowInput input = SurfaceConsumesInput();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: input.wrap(enabled: true, child: const Text('surface')),
        ),
      ),
    );
    expect(find.text('surface'), findsOneWidget);
  });

  testWidgets('forwarding reports positions in surface pixels', (
    WidgetTester tester,
  ) async {
    final List<Offset> seen = <Offset>[];
    // A 1080-wide phone surface shown in a 270-wide frame: a tap at the centre
    // of the frame is a tap at 540 on the phone, not 135. Getting this wrong
    // would put every touch in the wrong place.
    final WindowInput input = ForwardInputToBackend(
      surfacePixelSize: const Size(1080, 1920),
      onPointer: (PointerEvent _, Offset surface) => seen.add(surface),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 270,
              height: 480,
              child: input.wrap(
                enabled: true,
                child: const ColoredBox(
                  key: Key('surface'),
                  color: Color(0xFF000000),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    await tester.tapAt(tester.getCenter(find.byKey(const Key('surface'))));
    await tester.pump();

    expect(seen, isNotEmpty);
    expect(seen.first.dx, closeTo(540, 1));
    expect(seen.first.dy, closeTo(960, 1));
  });

  testWidgets('an unfocused window forwards nothing', (
    WidgetTester tester,
  ) async {
    final List<Offset> seen = <Offset>[];
    final WindowInput input = ForwardInputToBackend(
      surfacePixelSize: const Size(1080, 1920),
      onPointer: (PointerEvent _, Offset surface) => seen.add(surface),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 270,
            height: 480,
            child: input.wrap(
              enabled: false,
              child: const ColoredBox(
                key: Key('surface'),
                color: Color(0xFF000000),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.tapAt(tester.getCenter(find.byKey(const Key('surface'))));
    await tester.pump();

    expect(seen, isEmpty, reason: 'input belongs to the focused window only');
  });
}

/// The pointer mapping is separated out because a wrong phase or a wrong
/// coordinate space puts every touch in the wrong place on the phone, and no
/// widget test would catch that by eye.
void _mappingTests() {
  test('each pointer phase maps to the backend phase', () {
    const Offset at = Offset(120, 340);
    WindowPointerSample? map(PointerEvent e) => windowPointerSample(e, at);

    expect(map(const PointerDownEvent())?.phase, WindowPointerPhase.down);
    expect(map(const PointerMoveEvent())?.phase, WindowPointerPhase.move);
    expect(map(const PointerUpEvent())?.phase, WindowPointerPhase.up);
    expect(map(const PointerCancelEvent())?.phase, WindowPointerPhase.cancel);
    expect(map(const PointerScrollEvent())?.phase, WindowPointerPhase.scroll);
  });

  test('a hover is dropped rather than guessed at', () {
    expect(
      windowPointerSample(const PointerHoverEvent(), Offset.zero),
      isNull,
      reason: 'the backend has no phase for hover',
    );
  });

  test('the sample carries surface coordinates, not widget ones', () {
    final WindowPointerSample? s = windowPointerSample(
      const PointerDownEvent(position: Offset(10, 10), pointer: 7),
      const Offset(540, 960),
    );
    expect(s!.x, 540);
    expect(s.y, 960);
    expect(s.pointerId, 7);
  });

  test('scroll deltas survive the conversion', () {
    final WindowPointerSample? s = windowPointerSample(
      const PointerScrollEvent(scrollDelta: Offset(0, -53)),
      Offset.zero,
    );
    expect(s!.scrollDeltaY, -53);
  });
}

/// Key mapping. The guards that decide *whether* to forward live in the shell
/// and are covered in `shell_keyboard_test.dart`; this covers the conversion.
void _keyMappingTests() {
  test('down, repeat and up map to the backend phases', () {
    expect(
      windowKeySample(
        const KeyDownEvent(
          physicalKey: PhysicalKeyboardKey.keyA,
          logicalKey: LogicalKeyboardKey.keyA,
          timeStamp: Duration.zero,
        ),
      )?.phase,
      WindowKeyPhase.down,
    );
    expect(
      windowKeySample(
        const KeyUpEvent(
          physicalKey: PhysicalKeyboardKey.keyA,
          logicalKey: LogicalKeyboardKey.keyA,
          timeStamp: Duration.zero,
        ),
      )?.phase,
      WindowKeyPhase.up,
    );
  });

  test('a repeat is a down that says it is a repeat', () {
    // Not a separate phase: the far side needs to know it is held, and a
    // third phase would be a vocabulary the backend does not have.
    final WindowKeySample? s = windowKeySample(
      const KeyRepeatEvent(
        physicalKey: PhysicalKeyboardKey.keyA,
        logicalKey: LogicalKeyboardKey.keyA,
        timeStamp: Duration.zero,
      ),
    );
    expect(s!.phase, WindowKeyPhase.down);
    expect(s.repeat, isTrue);
  });

  test('the typed character survives, not just the key id', () {
    final WindowKeySample? s = windowKeySample(
      const KeyDownEvent(
        physicalKey: PhysicalKeyboardKey.keyA,
        logicalKey: LogicalKeyboardKey.keyA,
        character: 'a',
        timeStamp: Duration.zero,
      ),
    );
    expect(s!.character, 'a');
    expect(s.logicalKeyId, LogicalKeyboardKey.keyA.keyId);
    expect(s.physicalKeyId, PhysicalKeyboardKey.keyA.usbHidUsage);
  });

  testWidgets('a letterboxed surface maps taps to the video, not the frame', (
    WidgetTester tester,
  ) async {
    // The window is wider than the video, so `BoxFit.contain` centres the
    // picture with black bars left and right. Dividing by the whole widget —
    // which is what the mapping used to do — puts a tap on the centre of the
    // *frame* rather than the centre of the *picture*, and the error grows
    // with the mismatch.
    final List<Offset> seen = <Offset>[];
    final ForwardInputToBackend input = ForwardInputToBackend(
      surfacePixelSize: const Size(1080, 1920),
      onPointer: (PointerEvent _, Offset surface) => seen.add(surface),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              // Fits the default 800x600 test surface: a wider frame would
              // overflow and every coordinate below would be measured against
              // a clipped rect.
              width: 600,
              height: 320,
              child: input.wrap(
                enabled: true,
                child: const ColoredBox(
                  key: Key('surface'),
                  color: Color(0xFF000000),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    // Deliberately off centre. The centre is the fixed point of both the
    // correct and the incorrect mapping, so a centre tap cannot tell them
    // apart — the first version of this test passed against the bug.
    //
    // 1080x1920 contained in 600x320 scales by 1/6, so the picture is 180
    // wide and starts 210 in. A quarter across the picture is surface x=270;
    // dividing by the whole frame would report about 459.
    final Rect box = tester.getRect(find.byKey(const Key('surface')));
    await tester.tapAt(Offset(box.left + 210 + 45, box.center.dy));
    await tester.pump();

    expect(seen, isNotEmpty);
    expect(seen.first.dx, closeTo(270, 1), reason: 'a quarter across the video');
    expect(seen.first.dy, closeTo(960, 1));
  });

  testWidgets('a tap on the black bar clamps to the edge of the video', (
    WidgetTester tester,
  ) async {
    // It cannot be delivered faithfully — there is no app under a letterbox
    // bar — so the nearest edge is the honest answer. Mapping it into the
    // middle of the app, which is what dividing by the whole frame did, means
    // a click on nothing presses something.
    final List<Offset> seen = <Offset>[];
    final ForwardInputToBackend input = ForwardInputToBackend(
      surfacePixelSize: const Size(1080, 1920),
      onPointer: (PointerEvent _, Offset surface) => seen.add(surface),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 600,
              height: 320,
              child: input.wrap(
                enabled: true,
                child: const ColoredBox(
                  key: Key('surface'),
                  color: Color(0xFF000000),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    final Rect box = tester.getRect(find.byKey(const Key('surface')));
    // Well inside the left bar: the picture starts 210px in.
    await tester.tapAt(Offset(box.left + 20, box.center.dy));
    await tester.pump();

    expect(seen, isNotEmpty);
    expect(seen.first.dx, 0);
  });
}
