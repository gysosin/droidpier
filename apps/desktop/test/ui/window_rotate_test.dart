import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_dex_api/open_dex_api.dart';
import 'package:open_android_dex/ui/workspace/window_model.dart';

/// Turning a window portrait or landscape.
///
/// A one-shot orientation change, not a rotation lock: the Android app stays
/// free to request its own orientation afterwards.
void main() {
  const Size workspace = Size(1600, 900);

  test('a landscape window becomes taller than it is wide', () {
    const WindowGeometry landscape = WindowGeometry(
      x: 200,
      y: 100,
      width: 800,
      height: 500,
    );
    final WindowGeometry out = rotatedGeometry(landscape, workspace);
    expect(out.height, greaterThan(out.width));
  });

  test('a portrait window becomes wider than it is tall', () {
    const WindowGeometry portrait = WindowGeometry(
      x: 200,
      y: 100,
      width: 400,
      height: 700,
    );
    final WindowGeometry out = rotatedGeometry(portrait, workspace);
    expect(out.width, greaterThan(out.height));
  });

  test('rotating twice returns roughly where it started', () {
    const WindowGeometry start = WindowGeometry(
      x: 200,
      y: 100,
      width: 800,
      height: 500,
    );
    final WindowGeometry back = rotatedGeometry(
      rotatedGeometry(start, workspace),
      workspace,
    );
    expect(back.width, closeTo(start.width, 1));
    expect(back.height, closeTo(start.height, 1));
  });

  test('the centre is preserved', () {
    const WindowGeometry start = WindowGeometry(
      x: 300,
      y: 200,
      width: 600,
      height: 400,
    );
    final WindowGeometry out = rotatedGeometry(start, workspace);
    expect(out.x + out.width / 2, closeTo(start.x + start.width / 2, 1));
    expect(out.y + out.height / 2, closeTo(start.y + start.height / 2, 1));
  });

  test('the content aspect inverts, not the frame', () {
    // The title bar is chrome, not content. Swapping the frame's dimensions
    // would leave the video letterboxed by exactly the title bar's height.
    const double chrome = 34;
    const WindowGeometry start = WindowGeometry(
      x: 0,
      y: 0,
      width: 800,
      height: 500,
    );
    final WindowGeometry out = rotatedGeometry(start, workspace);
    expect(out.width, closeTo(start.height - chrome, 1));
    expect(out.height - chrome, closeTo(start.width, 1));
  });

  test('a rotation too tall for the desk is scaled to fit', () {
    // Rotating a very wide window would otherwise produce something taller
    // than the workspace, which cannot be dragged back into view.
    const WindowGeometry wide = WindowGeometry(
      x: 0,
      y: 0,
      width: 1500,
      height: 300,
    );
    final WindowGeometry out = rotatedGeometry(wide, workspace);
    expect(out.height, lessThanOrEqualTo(workspace.height));
    expect(out.width, lessThanOrEqualTo(workspace.width));
  });

  test('the result stays reachable on the desk', () {
    const WindowGeometry offEdge = WindowGeometry(
      x: 1500,
      y: 800,
      width: 400,
      height: 300,
    );
    final WindowGeometry out = rotatedGeometry(offEdge, workspace);
    expect(out.y, lessThan(workspace.height));
    expect(out.x, lessThan(workspace.width));
  });

  test('it never returns something below the minimum window size', () {
    const WindowGeometry tiny = WindowGeometry(
      x: 0,
      y: 0,
      width: 400,
      height: 60,
    );
    final WindowGeometry out = rotatedGeometry(tiny, workspace);
    expect(out.width, greaterThanOrEqualTo(WindowGeometry.minimumWidth));
    expect(out.height, greaterThanOrEqualTo(WindowGeometry.minimumHeight));
  });

  group('naming the action', () {
    test('a landscape window offers Portrait', () {
      expect(
        rotateActionLabel(
          const WindowGeometry(x: 0, y: 0, width: 800, height: 500),
        ),
        'Portrait',
      );
    });

    test('a portrait window offers Landscape', () {
      expect(
        rotateActionLabel(
          const WindowGeometry(x: 0, y: 0, width: 400, height: 700),
        ),
        'Landscape',
      );
    });
  });
}
