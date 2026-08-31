import 'package:open_dex_platform/open_dex_platform.dart';
import 'package:test/test.dart';

void main() {
  test('software-only FFmpeg does not use a capable host GPU', () async {
    final executor = _ProbeExecutor(
      accelerators: 'Hardware acceleration methods:\n',
    );
    final probe = SystemH264DecoderCapabilityProbe(executor: executor);
    expect(await probe.supportsVaapiH264('/test/software-ffmpeg'), isFalse);
    expect(executor.driverProbes, 0);
  });

  test('requires both a compiled VA-API backend and an H.264 driver', () async {
    final executor = _ProbeExecutor(
      accelerators: 'Hardware acceleration methods:\nvaapi\n',
    );
    final probe = SystemH264DecoderCapabilityProbe(executor: executor);
    expect(await probe.supportsVaapiH264('/test/vaapi-ffmpeg'), isTrue);
    expect(executor.driverProbes, 1);
  });

  test('does not treat a VA-API driver without H.264 as supported', () async {
    final executor = _ProbeExecutor(
      accelerators: 'vaapi\n',
      profiles: 'VAProfileVP9Profile0',
    );
    final probe = SystemH264DecoderCapabilityProbe(executor: executor);
    expect(await probe.supportsVaapiH264('/test/vp9-driver-ffmpeg'), isFalse);
  });
}

class _ProbeExecutor implements ProcessExecutor {
  _ProbeExecutor({
    required this.accelerators,
    this.profiles = 'VAProfileH264Main',
  });
  final String accelerators;
  final String profiles;
  int driverProbes = 0;
  @override
  Future<ProcessOutput> run(
    String executable,
    List<String> arguments, {
    Duration timeout = const Duration(seconds: 15),
    String? input,
  }) async {
    final String output;
    if (arguments.contains('-decoders')) {
      output = ' VFS..D h264 H.264 / AVC\n';
    } else if (arguments.contains('-hwaccels')) {
      output = accelerators;
    } else {
      driverProbes++;
      output = profiles;
    }
    return ProcessOutput(exitCode: 0, stdout: output, stderr: '');
  }
}
