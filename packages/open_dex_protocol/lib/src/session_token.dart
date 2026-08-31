import 'dart:convert';
import 'dart:math';

class SessionToken {
  SessionToken._();

  static String generate() {
    final random = Random.secure();
    final bytes = List<int>.generate(32, (_) => random.nextInt(256));
    return base64UrlEncode(bytes).replaceAll('=', '');
  }

  static bool matches(String expected, String candidate) {
    final expectedBytes = utf8.encode(expected);
    final candidateBytes = utf8.encode(candidate);
    var difference = expectedBytes.length ^ candidateBytes.length;
    final length = max(expectedBytes.length, candidateBytes.length);
    for (var index = 0; index < length; index++) {
      final left = index < expectedBytes.length ? expectedBytes[index] : 0;
      final right = index < candidateBytes.length ? candidateBytes[index] : 0;
      difference |= left ^ right;
    }
    return difference == 0;
  }
}
