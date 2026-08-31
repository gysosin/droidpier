class StreamBenchGateThresholds {
  const StreamBenchGateThresholds({
    required this.minimumFps,
    required this.maximumLatencyMs,
    required this.maximumOpenMs,
    required this.maximumResizeMs,
    required this.maximumCpuPercent,
    this.requiredBackend,
    this.maximumDropFraction = 0.02,
    this.refreshRateAllowance = 0.05,
  });

  final double minimumFps;
  final double maximumLatencyMs;
  final double maximumOpenMs;
  final double maximumResizeMs;
  final double maximumCpuPercent;
  final String? requiredBackend;
  final double maximumDropFraction;
  final double refreshRateAllowance;
}

List<String> streamBenchGateFailures(
  Map<String, Object?> output,
  StreamBenchGateThresholds thresholds,
) {
  final failures = <String>[];
  if (thresholds.requiredBackend case final required?) {
    final actual = output['backend'];
    if (actual != required) {
      failures.add('benchmark ran $actual backend; expected $required');
    }
  }

  final producedFps = output['produced_fps']! as num;
  final refreshHz = output['probe_refresh_hz']! as num;
  if (producedFps > refreshHz * (1 + thresholds.refreshRateAllowance)) {
    failures.add(
      'source produced more frames than the probe display can generate',
    );
  }

  final producedFrames = output['produced_frames']! as num;
  final droppedFrames = output['dropped']! as num;
  if (droppedFrames > producedFrames * thresholds.maximumDropFraction) {
    failures.add('texture drop ratio exceeded 2 percent');
  }
  if ((output['presented_fps']! as num) < thresholds.minimumFps) {
    failures.add('presented frame rate was below the target');
  }

  final latency = output['latency_ms_median'] as num?;
  if (latency == null || output['latency_status'] != 'ok') {
    failures.add('latency was not measured successfully');
  } else if (latency > thresholds.maximumLatencyMs) {
    failures.add('median latency exceeded the target');
  }
  if ((output['open_ms']! as num) > thresholds.maximumOpenMs) {
    failures.add('application open time exceeded the target');
  }
  if ((output['resize_ms']! as num) > thresholds.maximumResizeMs) {
    failures.add('resize time exceeded the target');
  }
  if ((output['cpu_pct']! as num) > thresholds.maximumCpuPercent) {
    failures.add('host CPU exceeded the target');
  }
  if ((output['input_p95_ms']! as num) > 50 ||
      (output['input_queue_max']! as num) > 4) {
    failures.add('input throughput exceeded its latency or queue target');
  }
  if (output['warmup'] != 'stable') {
    failures.add('frame production did not reach a stable warm-up plateau');
  }
  if ((output['phase_backlog']! as num) != 0) {
    failures.add('the frame pipeline retained a phase backlog');
  }
  if ((output['leaks']! as num) != 0) {
    failures.add('the run leaked a process, tunnel, or temporary directory');
  }
  return failures;
}
