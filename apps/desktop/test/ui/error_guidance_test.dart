import 'package:flutter_test/flutter_test.dart';
import 'package:open_android_dex/ui/util/error_guidance.dart';
import 'package:open_dex_api/open_dex_api.dart';

/// Every failure the backend can report has to end in something a person can
/// do. A code with no guidance is a dead end, which is the one thing the
/// interface rules here forbid outright.
void main() {
  OpenDexError err(OpenDexErrorCode code, {String message = 'It failed.'}) =>
      OpenDexError(code: code, message: message);

  test('every code a person can act on carries guidance', () {
    for (final OpenDexErrorCode code in OpenDexErrorCode.values) {
      // Cancelling is the one case where the person already knows why, and
      // telling them what to do about their own decision is noise.
      if (code == OpenDexErrorCode.cancelled) continue;
      final String? g = guidanceFor(err(code));
      expect(
        g,
        isNotNull,
        reason: '$code has no guidance — it would render as a dead end',
      );
      expect(g!.trim(), isNotEmpty, reason: '$code has empty guidance');
    }
  });

  test('cancelling says nothing, because the person did it', () {
    expect(guidanceFor(err(OpenDexErrorCode.cancelled)), isNull);
  });

  test('two phones is named as the cause, not described as a failure', () {
    final String g = guidanceFor(err(OpenDexErrorCode.multipleDevices))!;
    expect(g.toLowerCase(), contains('more than one'));
  });

  test('an unauthorised phone points at the phone, not the desktop', () {
    final String g = guidanceFor(err(OpenDexErrorCode.deviceUnauthorized))!;
    expect(g.toLowerCase(), contains('allow'));
  });

  test('guidance never repeats the message it sits under', () {
    // The note already prints error.message. Guidance that restates it wastes
    // the only line the person is going to read.
    for (final OpenDexErrorCode code in OpenDexErrorCode.values) {
      final String message = 'The Android companion could not start.';
      final String? g = guidanceFor(err(code, message: message));
      if (g == null) continue;
      expect(g.trim(), isNot(equalsIgnoringCase(message.trim())));
    }
  });
}
