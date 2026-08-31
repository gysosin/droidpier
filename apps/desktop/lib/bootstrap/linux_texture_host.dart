import 'dart:async';

import 'package:open_dex_api/open_dex_api.dart';
import 'package:open_dex_core/open_dex_core.dart';
import 'package:open_dex_texture/open_dex_texture.dart';

class LinuxTextureHost implements WindowTextureHost {
  const LinuxTextureHost({this.texture = const OpenDexTexture()});

  final OpenDexTexture texture;

  @override
  Future<int> createRawRgbaTexture({
    required String fifoPath,
    required WindowPixelSize pixelSize,
  }) => texture.create(
    fifoPath: fifoPath,
    width: pixelSize.width,
    height: pixelSize.height,
  );

  @override
  Future<void> waitForFirstFrame(
    int textureId, {
    required Duration timeout,
  }) async {
    final stopwatch = Stopwatch()..start();
    while (stopwatch.elapsed < timeout) {
      if (await texture.frameCount(textureId) > 0) return;
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    throw TimeoutException('The Android video stream produced no frame.');
  }

  @override
  Future<WindowTextureStats> stats(int textureId) async {
    final value = await texture.stats(textureId);
    return WindowTextureStats(
      frames: value.frames,
      presentedFrames: value.presentedFrames,
      lastFrameMonotonicUs: value.lastFrameMonotonicUs,
      centerLuma: value.centerLuma,
      probeLuma: value.probeLuma,
      droppedFrames: value.droppedFrames,
    );
  }

  @override
  Future<void> closeTexture(int textureId) => texture.close(textureId);
}
