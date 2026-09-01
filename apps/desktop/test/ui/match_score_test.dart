import 'package:flutter_test/flutter_test.dart';
import 'package:open_android_dex/ui/apps/app_ranking.dart';

/// The shared matcher.
///
/// Drawer search and the command palette rank different things — applications
/// and commands — but "did the person mean this?" is one question, and two
/// implementations of it would drift apart within a release.
void main() {
  test('a literal prefix outranks everything else', () {
    final double? prefix = scoreMatch('wal', 'Wallet');
    final double? mid = scoreMatch('wal', 'Firewall settings');
    expect(prefix, isNotNull);
    expect(mid, isNotNull);
    expect(prefix!, greaterThan(mid!));
  });

  test('initials match a run-together name', () {
    expect(scoreMatch('wa', 'WhatsApp'), isNotNull);
  });

  test('initials match across words', () {
    final double? acronym = scoreMatch('tw', 'Toggle window');
    expect(acronym, isNotNull);
  });

  test('a word start outranks a mid-word hit', () {
    final double? wordStart = scoreMatch('set', 'Open settings');
    final double? midWord = scoreMatch('set', 'Unset the thing');
    expect(wordStart!, greaterThan(midWord!));
  });

  test('scattered letters still match, and rank last', () {
    final double? scattered = scoreMatch('tgw', 'Toggle window');
    final double? wordStart = scoreMatch('win', 'Toggle window');
    expect(scattered, isNotNull);
    expect(wordStart!, greaterThan(scattered!));
  });

  test('no match returns null rather than zero', () {
    // Zero is a score. Null is an answer to a different question, and the
    // caller filters on it.
    expect(scoreMatch('zzzq', 'Toggle window'), isNull);
  });

  test('an empty query matches anything', () {
    expect(scoreMatch('', 'Toggle window'), isNotNull);
  });

  test('matching ignores case in both directions', () {
    expect(scoreMatch('WALLET', 'wallet'), isNotNull);
    expect(scoreMatch('wallet', 'WALLET'), isNotNull);
  });
}
