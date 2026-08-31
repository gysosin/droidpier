import 'package:flutter/services.dart';

class OpenDexTextureStats {
  const OpenDexTextureStats({
    required this.frames,
    required this.presentedFrames,
    required this.lastFrameMonotonicUs,
    required this.centerLuma,
    required this.probeLuma,
    required this.droppedFrames,
  });

  final int frames;
  final int presentedFrames;
  final int lastFrameMonotonicUs;
  final int centerLuma;
  final int probeLuma;
  final int droppedFrames;
}

/// Owns native Flutter textures backed by raw RGBA frame pipes.
class OpenDexTexture {
  const OpenDexTexture();

  static const MethodChannel _channel = MethodChannel('open_dex_texture');

  Future<int> create({
    required String fifoPath,
    required int width,
    required int height,
  }) async {
    final textureId = await _channel.invokeMethod<int>('create', {
      'fifoPath': fifoPath,
      'width': width,
      'height': height,
    });
    if (textureId == null) {
      throw PlatformException(
        code: 'texture-create-failed',
        message: 'The native texture registrar returned no texture id.',
      );
    }
    return textureId;
  }

  Future<void> close(int textureId) =>
      _channel.invokeMethod<void>('close', {'textureId': textureId});

  Future<int> frameCount(int textureId) async =>
      await _channel.invokeMethod<int>('frameCount', {
        'textureId': textureId,
      }) ??
      0;

  Future<OpenDexTextureStats> stats(int textureId) async {
    final result = await _channel.invokeMethod<Map<Object?, Object?>>('stats', {
      'textureId': textureId,
    });
    if (result == null) {
      throw PlatformException(
        code: 'texture-stats-failed',
        message: 'The native texture plugin returned no frame statistics.',
      );
    }
    int readInt(String key) {
      final value = result[key];
      if (value is int) return value;
      throw PlatformException(
        code: 'texture-stats-invalid',
        message: 'Texture statistic $key was not an integer.',
      );
    }

    return OpenDexTextureStats(
      frames: readInt('frames'),
      presentedFrames: readInt('presentedFrames'),
      lastFrameMonotonicUs: readInt('lastFrameMonotonicUs'),
      centerLuma: readInt('centerLuma'),
      probeLuma: readInt('probeLuma'),
      droppedFrames: readInt('droppedFrames'),
    );
  }
}
