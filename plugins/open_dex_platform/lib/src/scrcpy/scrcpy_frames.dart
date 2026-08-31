import 'dart:typed_data';

sealed class ScrcpyVideoEvent {
  const ScrcpyVideoEvent();
}

class ScrcpySessionMeta extends ScrcpyVideoEvent {
  const ScrcpySessionMeta({
    required this.width,
    required this.height,
    required this.clientResized,
  });

  final int width;
  final int height;
  final bool clientResized;
}

class ScrcpyVideoPacket extends ScrcpyVideoEvent {
  const ScrcpyVideoPacket({
    required this.pts,
    required this.isConfig,
    required this.isKeyFrame,
    required this.data,
  });

  final int pts;
  final bool isConfig;
  final bool isKeyFrame;
  final Uint8List data;
}
