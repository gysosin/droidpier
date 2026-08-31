import 'package:open_dex_api/open_dex_api.dart';
import 'package:open_dex_platform/open_dex_platform.dart';
import 'package:test/test.dart';

void main() {
  const portrait = WindowPixelSize(width: 720, height: 1280);
  const landscape = WindowPixelSize(width: 1280, height: 896);
  const fallback = WindowPixelSize(width: 1000, height: 1000);

  WindowPixelSize choose(String out) => DisplayOrientation.fromWmSize(
    out,
    portrait: portrait,
    landscape: landscape,
    fallback: fallback,
  );

  test('a tall physical size is portrait', () {
    expect(choose('Physical size: 1080x2340'), portrait);
  });

  test('a wide physical size is landscape', () {
    expect(choose('Physical size: 1920x1080'), landscape);
  });

  test('a square size counts as portrait, not landscape', () {
    expect(choose('Physical size: 1000x1000'), portrait);
  });

  test('the physical line wins over a leftover override', () {
    // A previous session may have forced a landscape override; orientation must
    // still follow the panel, which is portrait.
    const out = 'Physical size: 1080x2340\nOverride size: 1280x720';
    expect(choose(out), portrait);
  });

  test('falls back to a bare WxH when no physical line is present', () {
    expect(choose('1080x2340'), portrait);
  });

  test('unreadable output falls back rather than guessing', () {
    expect(choose('no dimensions here'), fallback);
    expect(choose(''), fallback);
  });
}
