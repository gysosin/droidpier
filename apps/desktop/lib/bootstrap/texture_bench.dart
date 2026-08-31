import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:open_dex_texture/open_dex_texture.dart';

const _sampleDuration = Duration(seconds: 10);
const _hardTimeout = Duration(seconds: 35);

Future<void> main(List<String> arguments) async {
  WidgetsFlutterBinding.ensureInitialized();
  final size = _BenchSize.parse(arguments);
  runApp(_TextureBench(width: size.width, height: size.height));
}

class _TextureBench extends StatefulWidget {
  const _TextureBench({required this.width, required this.height});

  final int width;
  final int height;

  @override
  State<_TextureBench> createState() => _TextureBenchState();
}

class _TextureBenchState extends State<_TextureBench> {
  static const _texture = OpenDexTexture();

  int? _textureId;
  Timer? _watchdog;

  @override
  void initState() {
    super.initState();
    _watchdog = Timer(_hardTimeout, () {
      stderr.writeln('texture_bench failed: hard timeout exceeded');
      exit(2);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => unawaited(_run()));
  }

  Future<void> _run() async {
    Directory? temporaryDirectory;
    Process? ffmpeg;
    var resultCode = 1;
    try {
      temporaryDirectory = await Directory.systemTemp.createTemp(
        'open-dex-texture-bench-',
      );
      final fifoPath = '${temporaryDirectory.path}/frames.rgba';
      final mkfifo = await Process.run('mkfifo', [fifoPath]);
      if (mkfifo.exitCode != 0) {
        throw StateError('mkfifo failed: ${mkfifo.stderr}');
      }

      final textureId = await _texture.create(
        fifoPath: fifoPath,
        width: widget.width,
        height: widget.height,
      );
      if (!mounted) return;
      setState(() => _textureId = textureId);
      await WidgetsBinding.instance.endOfFrame;

      ffmpeg = await Process.start('ffmpeg', [
        '-hide_banner',
        '-loglevel',
        'error',
        '-nostdin',
        '-y',
        '-re',
        '-f',
        'lavfi',
        '-i',
        'testsrc2=size=${widget.width}x${widget.height}:rate=60',
        '-t',
        '${_sampleDuration.inSeconds + 5}',
        '-f',
        'rawvideo',
        '-pix_fmt',
        'rgba',
        fifoPath,
      ]);
      ffmpeg.stdout.drain<void>();
      final errorOutput = ffmpeg.stderr
          .transform(systemEncoding.decoder)
          .join();

      await _waitForFirstFrame(textureId);
      final initial = await _texture.stats(textureId);
      final clockTicksPerSecond = await _clockTicksPerSecond();
      final cpuBefore = await _processCpuTicks();
      final elapsed = Stopwatch()..start();
      await Future<void>.delayed(_sampleDuration);
      final stats = await _texture.stats(textureId);
      final cpuAfter = await _processCpuTicks();
      elapsed.stop();

      final seconds =
          elapsed.elapsedMicroseconds / Duration.microsecondsPerSecond;
      final producedFrames = stats.frames - initial.frames;
      final presentedFrames = stats.presentedFrames - initial.presentedFrames;
      final droppedFrames = stats.droppedFrames - initial.droppedFrames;
      final producedFps = producedFrames / seconds;
      final presentedFps = presentedFrames / seconds;
      final cpuPercent =
          (cpuAfter - cpuBefore) / clockTicksPerSecond / seconds * 100;
      stdout.writeln(
        'texture_bench size=${widget.width}x${widget.height} '
        'produced_fps=${producedFps.toStringAsFixed(1)} '
        'presented_fps=${presentedFps.toStringAsFixed(1)} '
        'dropped=$droppedFrames '
        'cpu_pct=${cpuPercent.toStringAsFixed(1)}',
      );
      resultCode =
          presentedFps >= 55 &&
              (producedFrames == 0 || droppedFrames / producedFrames < .05)
          ? 0
          : 1;

      ffmpeg.kill(ProcessSignal.sigterm);
      await ffmpeg.exitCode.timeout(
        const Duration(seconds: 2),
        onTimeout: () {
          ffmpeg?.kill(ProcessSignal.sigkill);
          return -1;
        },
      );
      final ffmpegError = await errorOutput;
      if (producedFrames == 0 && ffmpegError.trim().isNotEmpty) {
        stderr.writeln(ffmpegError.trim());
      }
      ffmpeg = null;
      await _texture.close(textureId);
      _textureId = null;
    } on Object catch (error, stackTrace) {
      stderr.writeln('texture_bench failed: $error');
      stderr.writeln(stackTrace);
    } finally {
      ffmpeg?.kill(ProcessSignal.sigkill);
      if (_textureId case final textureId?) {
        await _texture.close(textureId);
      }
      if (temporaryDirectory != null) {
        await temporaryDirectory.delete(recursive: true);
      }
      _watchdog?.cancel();
      exit(resultCode);
    }
  }

  Future<int> _clockTicksPerSecond() async {
    final result = await Process.run('getconf', ['CLK_TCK']);
    final ticks = int.tryParse(result.stdout.toString().trim());
    if (result.exitCode != 0 || ticks == null || ticks < 1) {
      throw StateError('Could not read CLK_TCK from getconf.');
    }
    return ticks;
  }

  Future<void> _waitForFirstFrame(int textureId) async {
    final timeout = Stopwatch()..start();
    while (timeout.elapsed < const Duration(seconds: 5)) {
      if ((await _texture.stats(textureId)).frames > 0) return;
      await Future<void>.delayed(const Duration(milliseconds: 2));
    }
    throw TimeoutException('The texture source produced no first frame.');
  }

  Future<int> _processCpuTicks() async {
    final stat = await File('/proc/$pid/stat').readAsString();
    final commandEnd = stat.lastIndexOf(')');
    if (commandEnd < 0) throw const FormatException('Invalid /proc stat line.');
    final fields = stat.substring(commandEnd + 2).trim().split(' ');
    return int.parse(fields[11]) + int.parse(fields[12]);
  }

  @override
  void dispose() {
    _watchdog?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: ColoredBox(
        color: Colors.black,
        child: switch (_textureId) {
          final textureId? => Texture(
            textureId: textureId,
            filterQuality: FilterQuality.low,
          ),
          null => const SizedBox.expand(),
        },
      ),
    );
  }
}

class _BenchSize {
  const _BenchSize(this.width, this.height);

  factory _BenchSize.parse(List<String> arguments) {
    String? argument;
    for (final value in arguments) {
      if (value.startsWith('--size=')) {
        argument = value.substring('--size='.length);
        break;
      }
    }
    final match = RegExp(r'^(\d{2,4})x(\d{2,4})$')
        .firstMatch(argument ?? '1280x720');
    if (match == null) {
      throw const FormatException('Expected --size=WIDTHxHEIGHT.');
    }
    final width = int.parse(match.group(1)!);
    final height = int.parse(match.group(2)!);
    if (width > 4096 || height > 4096) {
      throw const FormatException(
        'Texture benchmark dimensions are too large.',
      );
    }
    return _BenchSize(width, height);
  }

  final int width;
  final int height;
}
