import 'package:flutter_test/flutter_test.dart';
import 'package:open_android_dex/bootstrap/stream_bench_gate.dart';

void main() {
  test('accepts a direct run below the refresh and drop ceilings', () {
    expect(streamBenchGateFailures(_passingOutput(), _thresholds), isEmpty);
  });

  test('names an impossible produced rate as its own failure', () {
    final output = _passingOutput()..['produced_fps'] = 63.1;

    expect(
      streamBenchGateFailures(output, _thresholds),
      contains(
        'source produced more frames than the probe display can generate',
      ),
    );
  });

  test('allows two percent drops but rejects a larger proportion', () {
    final atCeiling = _passingOutput()..['dropped'] = 24;
    final aboveCeiling = _passingOutput()..['dropped'] = 25;

    expect(streamBenchGateFailures(atCeiling, _thresholds), isEmpty);
    expect(
      streamBenchGateFailures(aboveCeiling, _thresholds),
      contains('texture drop ratio exceeded 2 percent'),
    );
  });

  test('rejects a legacy run when direct is required', () {
    final output = _passingOutput()..['backend'] = 'legacy';

    expect(
      streamBenchGateFailures(output, _thresholds),
      contains('benchmark ran legacy backend; expected direct'),
    );
  });
}

const _thresholds = StreamBenchGateThresholds(
  minimumFps: 55,
  maximumLatencyMs: 120,
  maximumOpenMs: 1500,
  maximumResizeMs: 500,
  maximumCpuPercent: 35,
  requiredBackend: 'direct',
);

Map<String, Object?> _passingOutput() => <String, Object?>{
  'backend': 'direct',
  'produced_fps': 60.0,
  'produced_frames': 1200,
  'probe_refresh_hz': 60.0,
  'presented_fps': 59.0,
  'dropped': 20,
  'latency_ms_median': 80.0,
  'latency_status': 'ok',
  'open_ms': 900.0,
  'resize_ms': 300.0,
  'cpu_pct': 20.0,
  'input_p95_ms': 1.0,
  'input_queue_max': 1,
  'warmup': 'stable',
  'phase_backlog': 0,
  'leaks': 0,
};
