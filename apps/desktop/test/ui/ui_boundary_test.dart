import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The UI consumes `OpenDexFacade` only.
///
/// This was written down as an ownership rule between two agents, and survives
/// the merge of those lanes for a better reason: a widget that starts a
/// process, opens a socket or reaches a platform channel cannot be rendered in
/// `preview_app.dart` or covered by a golden. The rule is what keeps the
/// interface testable without a phone attached.
///
/// It was being broken in exactly one place, and nothing noticed, because a
/// rule kept only in prose is a rule nobody runs.
void main() {
  test('no UI file starts a process or opens a socket', () {
    final Directory ui = Directory('lib/ui');
    final List<String> offences = <String>[];

    for (final FileSystemEntity entity in ui.listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      // The preview entrypoint is a developer harness, not shipped surface.
      if (entity.path.contains('/preview/')) continue;

      // Comments are prose, not calls. The first version of this test flagged
      // a doc comment that *described* the rule it was enforcing, which is the
      // kind of false positive that gets a rule test deleted rather than
      // fixed.
      final String source = entity
          .readAsStringSync()
          .split('\n')
          .where((String line) => !line.trimLeft().startsWith('//'))
          .join('\n');
      for (final (String pattern, String what) in <(String, String)>[
        ('Process.start', 'starts a process'),
        ('Process.run', 'runs a process'),
        ('Socket.connect', 'opens a socket'),
        ('MethodChannel(', 'uses a platform channel'),
      ]) {
        if (source.contains(pattern)) {
          offences.add('${entity.path} $what ($pattern)');
        }
      }
    }

    expect(
      offences,
      isEmpty,
      reason:
          'The UI must reach the host through OpenDexFacade so it stays\n'
          'renderable without a device. Add the capability to the facade\n'
          'rather than reaching around it.\n${offences.join('\n')}',
    );
  });
}
