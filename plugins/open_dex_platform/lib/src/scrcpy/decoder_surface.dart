import 'dart:io';

import 'package:open_dex_api/open_dex_api.dart';
import 'package:open_dex_core/open_dex_core.dart';

import '../process_executor.dart';
import 'h264_decoder_process.dart';
import 'scrcpy_frames.dart';

/// A decoded video surface: the pipe ffmpeg writes RGBA frames into, the
/// native texture reading from it, and the decoder process between the two.
class DecoderSurface {
  DecoderSurface({
    required this.directory,
    required this.fifoPath,
    required this.textureId,
    required this.pixelSize,
    required this.decoder,
  });

  final Directory directory;
  final int textureId;
  final WindowPixelSize pixelSize;
  H264Decoder decoder;
  int restartCount = 0;
  final String fifoPath;

  WindowSurface get windowSurface =>
      WindowSurface(textureId: textureId, pixelSize: pixelSize);

  Future<void> dispose(WindowTextureHost textureHost) async {
    await decoder.stop();
    await textureHost.closeTexture(textureId);
    if (await directory.exists()) await directory.delete(recursive: true);
  }
}

/// Opens [DecoderSurface]s: the pipe, the texture over it, then the decoder
/// feeding it. Shared by the window gateway and the display mirror, which
/// differ in what they stream but not in how a stream becomes pixels.
class DecoderSurfaceOpener {
  const DecoderSurfaceOpener({
    required this.textureHost,
    required this.decoderStarter,
    required this.ffmpegExecutable,
    required this.processExecutor,
  });

  final WindowTextureHost textureHost;
  final H264DecoderStarter decoderStarter;
  final String ffmpegExecutable;
  final ProcessExecutor processExecutor;

  /// [onFailure] builds the failure thrown when the pipe cannot be created,
  /// so each caller reports it against its own capability.
  Future<DecoderSurface> open(
    WindowPixelSize size,
    ScrcpyVideoPacket config, {
    required Future<void> Function() resetVideo,
    required BackendFailure Function(String message) onFailure,
  }) async {
    final directory = await Directory.systemTemp.createTemp('open-dex-direct-');
    final fifoPath = Platform.isWindows
        ? r'\\.\pipe\droidpier-' +
              directory.uri.pathSegments.where((s) => s.isNotEmpty).last
        : '${directory.path}/frames.rgba';
    // The Windows texture plugin owns its named-pipe server. POSIX pipes are
    // created here before native registration so the reader never sees a file.
    if (!Platform.isWindows) {
      final fifo = await processExecutor.run('/usr/bin/mkfifo', [
        '-m',
        '600',
        fifoPath,
      ], timeout: const Duration(seconds: 3));
      if (!fifo.succeeded) {
        await directory.delete(recursive: true);
        throw onFailure('The direct decoder frame pipe could not be created.');
      }
    }
    int? textureId;
    try {
      textureId = await textureHost.createRawRgbaTexture(
        fifoPath: fifoPath,
        pixelSize: size,
      );
      final decoder = await decoderStarter.start(
        ffmpegPath: ffmpegExecutable,
        fifoPath: fifoPath,
        latestConfig: config,
        resetVideo: resetVideo,
      );
      return DecoderSurface(
        directory: directory,
        fifoPath: fifoPath,
        textureId: textureId,
        pixelSize: size,
        decoder: decoder,
      );
    } on Object {
      if (textureId != null) await textureHost.closeTexture(textureId);
      await directory.delete(recursive: true);
      rethrow;
    }
  }
}
