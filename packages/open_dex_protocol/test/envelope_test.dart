import 'package:open_dex_protocol/open_dex_protocol.dart';
import 'package:test/test.dart';

void main() {
  test('round trips a version 1 envelope', () {
    final original = ProtocolEnvelope(
      id: 'request-1',
      type: 'agent.hello',
      timestamp: DateTime.utc(2026, 8, 24),
      data: const {'sdk': 33},
    );

    final decoded = ProtocolEnvelope.decode(original.encode());

    expect(decoded.version, 1);
    expect(decoded.id, 'request-1');
    expect(decoded.type, 'agent.hello');
    expect(decoded.data, {'sdk': 33});
  });

  test('rejects unsupported versions', () {
    expect(
      () => ProtocolEnvelope.decode(
        '{"v":2,"id":"1","type":"ping","timestamp":"2026-08-24T00:00:00Z","data":{}}',
      ),
      throwsA(isA<ProtocolException>()),
    );
  });
}
