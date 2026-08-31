import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:open_dex_api/open_dex_api.dart';
import 'package:open_dex_texture/open_dex_texture.dart';

import 'facade_factory.dart';
import 'probe_display_report.dart';
import 'stream_bench_gate.dart';
import 'window_backend_selection.dart';

const _companionPackage = 'io.github.shrey113.openandroiddex.companion';
const _probeComponent = '$_companionPackage/.StreamProbeActivity';
const _probeLogTag = 'OpenDexStreamProbe';
const _texture = OpenDexTexture();
var _probeReportSequence = 0;

Future<void> main(List<String> arguments) async {
  WidgetsFlutterBinding.ensureInitialized();
  final probeMode = _ProbeModeController();
  runApp(
    _StreamBench(
      facade: createBenchmarkFacade(
        additionalApplications: const [
          AndroidApplication(
            packageName: _companionPackage,
            label: 'DroidPier Stream Probe',
          ),
        ],
        onDisplayCreated: (device, displayId) async {
          await _launchProbeProcess(device.id, displayId, probeMode.value);
        },
      ),
      configuration: _BenchConfiguration.parse(arguments),
      probeMode: probeMode,
    ),
  );
}

Future<ProbeDisplayReport> _launchProbeProcess(
  String deviceId,
  int displayId,
  String mode,
) async {
  final adb = Platform.environment['ADB_PATH'] ?? 'adb';
  final reportId =
      '${pid}_${DateTime.now().microsecondsSinceEpoch}_${_probeReportSequence++}';
  final result = await Process.run(adb, [
    '-s',
    deviceId,
    'shell',
    'am',
    'start',
    '-W',
    '--display',
    '$displayId',
    '-n',
    _probeComponent,
    '--es',
    'mode',
    mode,
    '--es',
    'report_id',
    reportId,
  ]).timeout(const Duration(seconds: 15));
  if (result.exitCode != 0 || result.stdout.toString().contains('Error:')) {
    throw StateError('Probe launch failed: ${result.stderr}${result.stdout}');
  }
  final stopwatch = Stopwatch()..start();
  while (stopwatch.elapsed < const Duration(seconds: 5)) {
    final logs = await Process.run(adb, [
      '-s',
      deviceId,
      'logcat',
      '-d',
      '-v',
      'brief',
      '-s',
      '$_probeLogTag:I',
      '*:S',
    ]).timeout(const Duration(seconds: 5));
    if (logs.exitCode != 0) {
      throw StateError('Could not read probe display report: ${logs.stderr}');
    }
    final report = parseProbeDisplayReport(
      logs.stdout.toString(),
      reportId: reportId,
    );
    if (report != null) return report;
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }
  throw TimeoutException(
    'Probe did not report display $displayId refresh rate for $reportId.',
  );
}

class _BenchConfiguration {
  const _BenchConfiguration({
    required this.stage,
    required this.gate,
    required this.minimumFps,
    required this.maximumLatencyMs,
    required this.maximumOpenMs,
    required this.maximumResizeMs,
    required this.maximumCpuPercent,
    required this.fpsSeconds,
  });

  factory _BenchConfiguration.parse(List<String> arguments) {
    String value(String name, String fallback) {
      for (final argument in arguments) {
        if (argument.startsWith('--$name=')) {
          return argument.substring(name.length + 3);
        }
      }
      return fallback;
    }

    return _BenchConfiguration(
      stage: value('stage', 'baseline'),
      gate: !arguments.contains('--no-gate'),
      minimumFps: double.parse(value('min-fps', '55')),
      maximumLatencyMs: double.parse(value('max-latency-ms', '120')),
      maximumOpenMs: double.parse(value('max-open-ms', '1500')),
      maximumResizeMs: double.parse(value('max-resize-ms', '500')),
      maximumCpuPercent: double.parse(value('max-cpu-pct', '35')),
      fpsSeconds: int.parse(value('fps-seconds', '20')),
    );
  }

  final String stage;
  final bool gate;
  final double minimumFps;
  final double maximumLatencyMs;
  final double maximumOpenMs;
  final double maximumResizeMs;
  final double maximumCpuPercent;
  final int fpsSeconds;
}

class _StreamBench extends StatefulWidget {
  const _StreamBench({
    required this.facade,
    required this.configuration,
    required this.probeMode,
  });

  final OpenDexFacade facade;
  final _BenchConfiguration configuration;
  final _ProbeModeController probeMode;

  @override
  State<_StreamBench> createState() => _StreamBenchState();
}

class _StreamBenchState extends State<_StreamBench> {
  StreamSubscription<OpenDexSnapshot>? _states;
  OpenDexSnapshot _snapshot = const OpenDexSnapshot();
  Timer? _watchdog;
  bool _finished = false;

  @override
  void initState() {
    super.initState();
    _snapshot = widget.facade.snapshot;
    _states = widget.facade.states.listen((snapshot) {
      _snapshot = snapshot;
      if (mounted) setState(() {});
    });
    _watchdog = Timer(
      const Duration(minutes: 4),
      () => unawaited(_abortForTimeout()),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) => unawaited(_run()));
  }

  Future<void> _run() async {
    final initialTemporaryDirectories = await _windowTemporaryDirectories();
    final backend = resolveWindowBackend(Platform.environment).name;
    Map<String, Object?> output;
    var resultCode = 2;
    try {
      _requireSuccess(
        await widget.facade.discoverDevices(),
        'device discovery',
      );
      _requireSuccess(
        await widget.facade.connectSelectedDevice(),
        'device connection',
      );
      final device = widget.facade.snapshot.selectedDevice;
      if (device == null) throw StateError('No selected device after boot.');
      if (!widget.facade.snapshot.applications.any(
        (application) => application.packageName == _companionPackage,
      )) {
        throw StateError('The benchmark companion is absent from the catalog.');
      }

      final openTimer = Stopwatch()..start();
      final launched = await widget.facade.launchApplication(_companionPackage);
      final sessionId = _successValue(launched, 'probe window launch');
      final window = _window(sessionId);
      final surface = window.surface;
      final displayId = window.displayId;
      if (surface == null || displayId == null) {
        throw StateError('The probe window has no Android display or texture.');
      }
      final beforeProbeLaunch = await _texture.stats(surface.textureId);
      final probeDisplay = await _launchProbeProcess(
        device.id,
        displayId,
        'motion',
      );
      if (probeDisplay.displayId != displayId) {
        throw StateError(
          'Probe reported display ${probeDisplay.displayId}, expected $displayId.',
        );
      }
      await _waitForFrameAfter(surface.textureId, beforeProbeLaunch.frames);
      openTimer.stop();

      final warmup = await _waitForSteadyFrameProduction(surface.textureId);
      final fps = await _measureFpsAndCpu(surface.textureId);
      await _launchProbeProcess(device.id, displayId, 'latency');
      await _waitForFrameAfter(surface.textureId, fps.finalFrameCount);
      final phaseBacklog = !await _waitForFrameQuiescence(
        surface.textureId,
        timeout: const Duration(seconds: 2),
      );
      List<double>? latency;
      var latencyStatus = 'not_measured_backlog';
      if (!phaseBacklog) {
        try {
          latency = await _measureLatency(sessionId, surface);
          latencyStatus = 'ok';
        } on TimeoutException {
          latencyStatus = 'not_measured_timeout';
        }
      }
      final input = await _measureInputThroughput(sessionId, surface);

      widget.probeMode.value = 'motion';
      await _launchProbeProcess(device.id, displayId, 'motion');
      final beforeResize = await _texture.stats(surface.textureId);
      await _waitForFrameAfter(surface.textureId, beforeResize.frames);
      final resizeTimer = Stopwatch()..start();
      _requireSuccess(
        await widget.facade.moveWindow(
          sessionId,
          const WindowGeometry(x: 64, y: 64, width: 500, height: 800),
        ),
        'window resize',
      );
      final resized = _window(sessionId).surface;
      if (resized == null) {
        throw StateError('Resize removed the video surface.');
      }
      await _waitForAnyFrame(resized.textureId);
      resizeTimer.stop();

      _requireSuccess(
        await widget.facade.closeWindow(sessionId),
        'window close',
      );
      await widget.facade.dispose();
      await Future<void>.delayed(const Duration(milliseconds: 250));

      final leaks = await _countLeaks(initialTemporaryDirectories, device.id);
      output = <String, Object?>{
        'stage': widget.configuration.stage,
        'backend': backend,
        'probe_display_id': probeDisplay.displayId,
        'probe_refresh_hz': _round1(probeDisplay.refreshHz),
        'produced_fps': _round1(fps.mean),
        'produced_frames': fps.producedFrames,
        'fps_mean': _round1(fps.mean),
        'fps_min': _round1(fps.minimum),
        'presented_fps': _round1(fps.presentedMean),
        'presented_fps_min': _round1(fps.presentedMinimum),
        'dropped': fps.dropped,
        'latency_ms_median': latency == null
            ? null
            : _round1(_percentile(latency, 50)),
        'latency_ms_p90': latency == null
            ? null
            : _round1(_percentile(latency, 90)),
        'latency_status': latencyStatus,
        'open_ms': _round1(openTimer.elapsedMicroseconds / 1000),
        'resize_ms': _round1(resizeTimer.elapsedMicroseconds / 1000),
        'cpu_pct': _round1(fps.cpuPercent),
        'input_p95_ms': _round1(_percentile(input.durationsMs, 95)),
        'input_queue_max': input.maximumPending,
        'warmup': warmup,
        'phase_backlog': phaseBacklog ? 1 : 0,
        'leaks': leaks,
      };
      final gateFailures = widget.configuration.gate
          ? streamBenchGateFailures(
              output,
              StreamBenchGateThresholds(
                minimumFps: widget.configuration.minimumFps,
                maximumLatencyMs: widget.configuration.maximumLatencyMs,
                maximumOpenMs: widget.configuration.maximumOpenMs,
                maximumResizeMs: widget.configuration.maximumResizeMs,
                maximumCpuPercent: widget.configuration.maximumCpuPercent,
                requiredBackend:
                    widget.configuration.stage == '2' ||
                        widget.configuration.stage == 'final'
                    ? 'direct'
                    : null,
              ),
            )
          : const <String>[];
      output['gate_failures'] = gateFailures;
      resultCode = gateFailures.isEmpty ? 0 : 1;
    } on Object catch (error, stackTrace) {
      await _bestEffortDispose();
      output = <String, Object?>{
        'stage': widget.configuration.stage,
        'backend': backend,
        'error': error.toString(),
        'leaks': null,
      };
      stderr.writeln(stackTrace);
    }

    _finished = true;
    _watchdog?.cancel();
    await _states?.cancel();
    stdout.writeln(jsonEncode(output));
    exit(resultCode);
  }

  Future<_FpsMeasurement> _measureFpsAndCpu(int textureId) async {
    final duration = Duration(seconds: widget.configuration.fpsSeconds);
    final initial = await _texture.stats(textureId);
    final cpuBefore = await _processTreeCpuTicks(pid);
    final clockTicks = await _clockTicksPerSecond();
    final stopwatch = Stopwatch()..start();
    var previousFrames = initial.frames;
    var previousPresentedFrames = initial.presentedFrames;
    var previousElapsed = Duration.zero;
    var minimum = double.infinity;
    var presentedMinimum = double.infinity;
    for (var second = 1; second <= duration.inSeconds; second += 1) {
      final target = Duration(seconds: second);
      final remaining = target - stopwatch.elapsed;
      if (remaining > Duration.zero) await Future<void>.delayed(remaining);
      final current = await _texture.stats(textureId);
      final currentElapsed = stopwatch.elapsed;
      final intervalSeconds =
          (currentElapsed - previousElapsed).inMicroseconds /
          Duration.microsecondsPerSecond;
      final intervalFps = (current.frames - previousFrames) / intervalSeconds;
      final presentedIntervalFps =
          (current.presentedFrames - previousPresentedFrames) / intervalSeconds;
      if (intervalFps < minimum) minimum = intervalFps;
      if (presentedIntervalFps < presentedMinimum) {
        presentedMinimum = presentedIntervalFps;
      }
      previousFrames = current.frames;
      previousPresentedFrames = current.presentedFrames;
      previousElapsed = currentElapsed;
    }
    final finalStats = await _texture.stats(textureId);
    stopwatch.stop();
    final cpuAfter = await _processTreeCpuTicks(pid);
    final seconds =
        stopwatch.elapsedMicroseconds / Duration.microsecondsPerSecond;
    return _FpsMeasurement(
      mean: (finalStats.frames - initial.frames) / seconds,
      minimum: minimum,
      presentedMean:
          (finalStats.presentedFrames - initial.presentedFrames) / seconds,
      presentedMinimum: presentedMinimum,
      dropped: finalStats.droppedFrames - initial.droppedFrames,
      producedFrames: finalStats.frames - initial.frames,
      cpuPercent: (cpuAfter - cpuBefore) / clockTicks / seconds * 100,
      finalFrameCount: finalStats.frames,
    );
  }

  Future<String> _waitForSteadyFrameProduction(int textureId) async {
    var previous = await _texture.stats(textureId);
    final stopwatch = Stopwatch()..start();
    var previousElapsed = Duration.zero;
    final rates = <double>[];
    for (var second = 1; second <= 15; second += 1) {
      final target = Duration(seconds: second);
      final remaining = target - stopwatch.elapsed;
      if (remaining > Duration.zero) await Future<void>.delayed(remaining);
      final current = await _texture.stats(textureId);
      final currentElapsed = stopwatch.elapsed;
      final intervalSeconds =
          (currentElapsed - previousElapsed).inMicroseconds /
          Duration.microsecondsPerSecond;
      final rate = (current.frames - previous.frames) / intervalSeconds;
      previous = current;
      previousElapsed = currentElapsed;
      rates.add(rate);
      if (rates.length > 3) rates.removeAt(0);
      if (rates.length == 3) {
        final minimum = rates.reduce((a, b) => a < b ? a : b);
        final maximum = rates.reduce((a, b) => a > b ? a : b);
        final mean = rates.reduce((a, b) => a + b) / rates.length;
        final tolerance = (mean * 0.1).clamp(4.0, double.infinity);
        if (maximum - minimum <= tolerance) return 'stable';
      }
    }
    return 'unstable';
  }

  Future<List<double>> _measureLatency(
    String sessionId,
    WindowSurface surface,
  ) async {
    await Future<void>.delayed(const Duration(milliseconds: 250));
    final samples = <double>[];
    for (var iteration = 0; iteration < 20; iteration += 1) {
      final before = await _texture.stats(surface.textureId);
      final timer = Stopwatch()..start();
      _requireSuccess(
        await widget.facade.sendPointer(
          sessionId,
          WindowPointerSample(
            phase: WindowPointerPhase.down,
            x: surface.pixelSize.width / 2,
            y: surface.pixelSize.height / 2,
            pointerId: 0,
          ),
        ),
        'latency pointer down',
      );
      final up = widget.facade.sendPointer(
        sessionId,
        WindowPointerSample(
          phase: WindowPointerPhase.up,
          x: surface.pixelSize.width / 2,
          y: surface.pixelSize.height / 2,
          pointerId: 0,
        ),
      );
      try {
        await _waitForLumaChange(surface.textureId, before.centerLuma);
        timer.stop();
      } finally {
        _requireSuccess(await up, 'latency pointer up');
      }
      samples.add(timer.elapsedMicroseconds / 1000);
    }
    return samples;
  }

  Future<_InputMeasurement> _measureInputThroughput(
    String sessionId,
    WindowSurface surface,
  ) async {
    const duration = Duration(seconds: 10);
    const interval = Duration(microseconds: 16667);
    final stopwatch = Stopwatch()..start();
    final futures = <Future<void>>[];
    final durations = <double>[];
    var pending = 0;
    var maximumPending = 0;
    var sequence = 0;
    while (stopwatch.elapsed < duration) {
      final target = interval * sequence;
      final wait = target - stopwatch.elapsed;
      if (wait > Duration.zero) await Future<void>.delayed(wait);
      pending += 1;
      if (pending > maximumPending) maximumPending = pending;
      final callTimer = Stopwatch()..start();
      final x = (sequence * 13 % surface.pixelSize.width).toDouble();
      final future = widget.facade
          .sendPointer(
            sessionId,
            WindowPointerSample(
              phase: WindowPointerPhase.move,
              x: x,
              y: surface.pixelSize.height / 2,
              pointerId: 0,
            ),
          )
          .then((result) {
            callTimer.stop();
            pending -= 1;
            _requireSuccess(result, 'input throughput move');
            durations.add(callTimer.elapsedMicroseconds / 1000);
          });
      futures.add(future);
      sequence += 1;
    }
    await Future.wait(futures);
    return _InputMeasurement(
      durationsMs: durations,
      maximumPending: maximumPending,
    );
  }

  Future<void> _waitForAnyFrame(int textureId) async {
    final initial = await _texture.stats(textureId);
    if (initial.frames > 0) return;
    await _waitForFrameAfter(textureId, 0);
  }

  Future<void> _waitForFrameAfter(int textureId, int frame) async {
    final timeout = Stopwatch()..start();
    while (timeout.elapsed < const Duration(seconds: 10)) {
      if ((await _texture.stats(textureId)).frames > frame) return;
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    throw TimeoutException('The texture produced no new probe frame.');
  }

  Future<void> _waitForLumaChange(int textureId, int previous) async {
    final timeout = Stopwatch()..start();
    while (timeout.elapsed < const Duration(seconds: 3)) {
      final current = await _texture.stats(textureId);
      if ((current.centerLuma < 128) != (previous < 128)) return;
      await Future<void>.delayed(const Duration(milliseconds: 2));
    }
    final current = await _texture.stats(textureId);
    throw TimeoutException(
      'The latency probe did not change luma '
      '(before=$previous center=${current.centerLuma} '
      'probe=${current.probeLuma} frames=${current.frames}).',
    );
  }

  Future<bool> _waitForFrameQuiescence(
    int textureId, {
    required Duration timeout,
  }) async {
    final stopwatch = Stopwatch()..start();
    while (stopwatch.elapsed < timeout) {
      final before = await _texture.stats(textureId);
      await Future<void>.delayed(const Duration(milliseconds: 350));
      final after = await _texture.stats(textureId);
      if (after.frames == before.frames) return true;
    }
    return false;
  }

  WindowSessionState _window(String sessionId) => widget.facade.snapshot.windows
      .singleWhere((window) => window.id == sessionId);

  T _successValue<T>(CommandResult<T> result, String operation) {
    if (result case CommandSuccess<T>(:final value)) return value;
    _requireSuccess(result, operation);
    throw StateError('$operation returned no value.');
  }

  void _requireSuccess<T>(CommandResult<T> result, String operation) {
    if (result case CommandFailure<T>(:final error)) {
      throw StateError(
        '$operation failed: ${error.message} ${error.technicalDetails ?? ''}',
      );
    }
  }

  Future<int> _countLeaks(
    Set<String> initialDirectories,
    String deviceId,
  ) async {
    var leaks = 0;
    final descendants = await _descendantPids(pid);
    for (final child in descendants) {
      final command = await _readCommandLine(child);
      if (command.contains('ffmpeg') ||
          command.contains('scrcpy') ||
          command.contains('adb -s $deviceId shell')) {
        leaks += 1;
      }
    }
    final remainingDirectories = await _windowTemporaryDirectories();
    leaks += remainingDirectories.difference(initialDirectories).length;
    final adb = Platform.environment['ADB_PATH'] ?? 'adb';
    final reverse = await Process.run(adb, [
      '-s',
      deviceId,
      'reverse',
      '--list',
    ]);
    for (final line in const LineSplitter().convert(
      reverse.stdout.toString(),
    )) {
      if (line.trim().isNotEmpty &&
          !line.contains('tcp:3698') &&
          !line.contains('tcp:3699')) {
        leaks += 1;
      }
    }
    return leaks;
  }

  Future<void> _abortForTimeout() async {
    if (_finished) return;
    stderr.writeln('stream_bench failed: hard timeout exceeded');
    await _bestEffortDispose();
    exit(2);
  }

  Future<void> _bestEffortDispose() async {
    try {
      await widget.facade.dispose().timeout(const Duration(seconds: 15));
    } on Object {
      // The benchmark error remains the primary diagnostic.
    }
  }

  @override
  void dispose() {
    _watchdog?.cancel();
    unawaited(_states?.cancel());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final surfaces = _snapshot.windows
        .map((window) => window.surface)
        .whereType<WindowSurface>()
        .toList();
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: ColoredBox(
        color: Colors.black,
        child: surfaces.isEmpty
            ? const SizedBox.expand()
            : Texture(
                textureId: surfaces.last.textureId,
                filterQuality: FilterQuality.low,
              ),
      ),
    );
  }
}

class _FpsMeasurement {
  const _FpsMeasurement({
    required this.mean,
    required this.minimum,
    required this.presentedMean,
    required this.presentedMinimum,
    required this.dropped,
    required this.producedFrames,
    required this.cpuPercent,
    required this.finalFrameCount,
  });

  final double mean;
  final double minimum;
  final double presentedMean;
  final double presentedMinimum;
  final int dropped;
  final int producedFrames;
  final double cpuPercent;
  final int finalFrameCount;
}

class _InputMeasurement {
  const _InputMeasurement({
    required this.durationsMs,
    required this.maximumPending,
  });

  final List<double> durationsMs;
  final int maximumPending;
}

class _ProbeModeController {
  String value = 'motion';
}

double _percentile(List<double> source, int percentile) {
  if (source.isEmpty) return double.infinity;
  final values = [...source]..sort();
  final index = ((values.length - 1) * percentile / 100).round();
  return values[index];
}

double _round1(num value) => (value * 10).round() / 10;

Future<int> _clockTicksPerSecond() async {
  final result = await Process.run('getconf', ['CLK_TCK']);
  final ticks = int.tryParse(result.stdout.toString().trim());
  if (result.exitCode != 0 || ticks == null || ticks < 1) {
    throw StateError('Could not read CLK_TCK from getconf.');
  }
  return ticks;
}

Future<int> _processTreeCpuTicks(int rootPid) async {
  final descendants = await _descendantPids(rootPid);
  var ticks = await _cpuTicks(rootPid) ?? 0;
  for (final child in descendants) {
    ticks += await _cpuTicks(child) ?? 0;
  }
  return ticks;
}

Future<Set<int>> _descendantPids(int rootPid) async {
  final children = <int, List<int>>{};
  await for (final entity in Directory('/proc').list()) {
    final processId = int.tryParse(entity.path.split('/').last);
    if (processId == null) continue;
    final fields = await _statFields(processId);
    if (fields == null) continue;
    final parent = int.tryParse(fields[1]);
    if (parent != null) children.putIfAbsent(parent, () => []).add(processId);
  }
  final result = <int>{};
  final pending = <int>[rootPid];
  while (pending.isNotEmpty) {
    final parent = pending.removeLast();
    for (final child in children[parent] ?? const <int>[]) {
      if (result.add(child)) pending.add(child);
    }
  }
  return result;
}

Future<int?> _cpuTicks(int processId) async {
  final fields = await _statFields(processId);
  if (fields == null) return null;
  final userTicks = int.tryParse(fields[11]);
  final systemTicks = int.tryParse(fields[12]);
  if (userTicks == null || systemTicks == null) return null;
  return userTicks + systemTicks;
}

Future<List<String>?> _statFields(int processId) async {
  try {
    final stat = await File('/proc/$processId/stat').readAsString();
    final commandEnd = stat.lastIndexOf(')');
    if (commandEnd < 0) return null;
    return stat.substring(commandEnd + 2).trim().split(' ');
  } on FileSystemException {
    return null;
  }
}

Future<String> _readCommandLine(int processId) async {
  try {
    final bytes = await File('/proc/$processId/cmdline').readAsBytes();
    return systemEncoding.decode([
      for (final byte in bytes) byte == 0 ? 32 : byte,
    ]);
  } on FileSystemException {
    return '';
  }
}

Future<Set<String>> _windowTemporaryDirectories() async {
  final result = <String>{};
  await for (final entity in Directory.systemTemp.list()) {
    if (entity is Directory &&
        entity.path
            .split(Platform.pathSeparator)
            .last
            .startsWith('open-dex-window-')) {
      result.add(entity.path);
    }
  }
  return result;
}
