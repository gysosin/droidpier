import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:open_dex_api/open_dex_api.dart';
import 'package:open_dex_core/open_dex_core.dart';
import 'package:open_dex_platform/open_dex_platform.dart';
import 'package:test/test.dart';

import 'scrcpy_fakes.dart';

/// The mirror is the window pipeline with the parts a view-only stream of the
/// phone's own display does not need removed: no virtual display, no control
/// socket, no input. What is left still has to come up on the first decoded
/// frame, follow a rotation, and tear down completely.
void main() {
  DirectScrcpyDisplayMirrorGateway gateway({
    required _FakeMirrorStarter starter,
    required FakeDecoderStarter decoders,
    required FakeTextureHost textures,
  }) => DirectScrcpyDisplayMirrorGateway(
    mirrorStarter: starter,
    decoderStarter: decoders,
    serverJarPath: '/runtime/scrcpy-server',
    ffmpegExecutable: '/runtime/ffmpeg',
    textureHost: textures,
    processExecutor: const FakeExecutor(),
    surfaceRetireDelay: Duration.zero,
  );

  test(
    'start resolves on the first decoded frame of the phone display',
    () async {
      final starter = _FakeMirrorStarter();
      final decoders = FakeDecoderStarter();
      final textures = FakeTextureHost();
      final mirror = gateway(
        starter: starter,
        decoders: decoders,
        textures: textures,
      );
      addTearDown(mirror.dispose);
      final firstFrame = Completer<void>();
      textures.frameGates[91] = firstFrame;

      final start = mirror.start(_device);
      await waitUntil(() => textures.waited.contains(91));
      var started = false;
      unawaited(start.then((_) => started = true));
      await Future<void>.delayed(Duration.zero);
      expect(started, isFalse, reason: 'no frame yet, so not streaming yet');

      firstFrame.complete();
      final session = await start;
      expect(session.id, startsWith('mirror-'));
      expect(session.surface.textureId, 91);
      expect(session.surface.pixelSize.width, 540);
      expect(session.surface.pixelSize.height, 1170);
      expect(starter.maxSize, 1080);
      expect(starter.maxFps, 30);
      expect(starter.connections, 1, reason: 'one socket: video only');
      expect(decoders.decoder.initialConfig?.isConfig, isTrue);
      expect(decoders.decoder.packets.single.isKeyFrame, isTrue);
    },
  );

  test('one mirror at a time', () async {
    final starter = _FakeMirrorStarter();
    final mirror = gateway(
      starter: starter,
      decoders: FakeDecoderStarter(),
      textures: FakeTextureHost(),
    );
    addTearDown(mirror.dispose);
    await mirror.start(_device);
    await expectLater(mirror.start(_device), throwsA(isA<BackendFailure>()));
    expect(starter.starts, 1);
  });

  test('stop releases the decoder, the texture and the server', () async {
    final starter = _FakeMirrorStarter();
    final decoders = FakeDecoderStarter();
    final textures = FakeTextureHost();
    final mirror = gateway(
      starter: starter,
      decoders: decoders,
      textures: textures,
    );
    addTearDown(mirror.dispose);
    final session = await mirror.start(_device);
    await mirror.stop(session.id);
    expect(decoders.decoder.stopped, isTrue);
    expect(textures.closed, [91]);
    expect(starter.handle.stopped, isTrue);
    // A second stop of the same id is a no-op, not an error.
    await mirror.stop(session.id);
  });

  test('server death publishes exit 21 and cleans the session', () async {
    final starter = _FakeMirrorStarter();
    final decoders = FakeDecoderStarter();
    final textures = FakeTextureHost();
    final mirror = gateway(
      starter: starter,
      decoders: decoders,
      textures: textures,
    );
    addTearDown(mirror.dispose);
    final exits = <MirrorBackendExit>[];
    mirror.exits.listen(exits.add);
    final session = await mirror.start(_device);
    starter.handle.fail(1);
    await waitUntil(() => exits.isNotEmpty);
    expect(exits.single.sessionId, session.id);
    expect(exits.single.exitCode, 21);
    expect(textures.closed, [91]);
    expect(decoders.decoder.stopped, isTrue);
  });

  test('decoder death ends the mirror with exit 22', () async {
    // Without a control socket there is no way to ask the phone for a fresh
    // key frame, so a decoder restart would only ever decode garbage. The
    // honest outcome is an exit the desk can offer to retry.
    final starter = _FakeMirrorStarter();
    final decoders = FakeDecoderStarter();
    final textures = FakeTextureHost();
    final mirror = gateway(
      starter: starter,
      decoders: decoders,
      textures: textures,
    );
    addTearDown(mirror.dispose);
    final exits = <MirrorBackendExit>[];
    mirror.exits.listen(exits.add);
    await mirror.start(_device);
    decoders.decoder.fail(1);
    await waitUntil(() => exits.isNotEmpty);
    expect(exits.single.exitCode, 22);
    expect(decoders.decoders, hasLength(1), reason: 'no restart attempted');
    expect(starter.handle.stopped, isTrue);
  });

  test('a rotated phone gets a new surface and the old one retires', () async {
    final starter = _FakeMirrorStarter();
    final decoders = FakeDecoderStarter();
    final textures = FakeTextureHost();
    final mirror = gateway(
      starter: starter,
      decoders: decoders,
      textures: textures,
    );
    addTearDown(mirror.dispose);
    final updates = <MirrorBackendSession>[];
    mirror.surfaceUpdates.listen(updates.add);
    final session = await mirror.start(_device);

    starter.sendVideo([
      sessionMeta(width: 1170, height: 540),
      videoPacket(config: true, bytes: [0, 0, 0, 1, 103]),
      videoPacket(key: true, bytes: [0, 0, 0, 1, 101]),
    ]);
    await waitUntil(() => updates.isNotEmpty);
    expect(updates.single.id, session.id);
    expect(updates.single.surface.textureId, 92);
    expect(updates.single.surface.pixelSize.width, 1170);
    expect(updates.single.surface.pixelSize.height, 540);
    await waitUntil(() => textures.closed.contains(91));
    expect(decoders.decoders, hasLength(2));
    expect(decoders.decoders.first.stopped, isTrue);
    expect(decoders.decoders.last.packets.single.isKeyFrame, isTrue);
  });

  test('dispose stops a running mirror', () async {
    final starter = _FakeMirrorStarter();
    final textures = FakeTextureHost();
    final mirror = gateway(
      starter: starter,
      decoders: FakeDecoderStarter(),
      textures: textures,
    );
    await mirror.start(_device);
    await mirror.dispose();
    expect(textures.closed, [91]);
    expect(starter.handle.stopped, isTrue);
  });
}

const _device = DeviceSummary(
  id: 'device-1',
  name: 'Phone',
  connectionKind: DeviceConnectionKind.usb,
  status: DeviceStatus.authorized,
);

/// Plays the part of scrcpy-server mirroring display 0: one video socket, a
/// session header at the phone's scaled size, a config packet, a key frame.
class _FakeMirrorStarter implements ScrcpyMirrorStarter {
  final handle = FakeServerHandle();
  Socket? _video;
  int connections = 0;
  int starts = 0;
  int? maxSize;
  int? maxFps;

  @override
  Future<ScrcpyServerSession> startMirror({
    required DeviceSummary device,
    required String serverJarPath,
    required int hostPort,
    required String scid,
    int maxSize = 1080,
    int maxFps = 30,
  }) async {
    starts++;
    this.maxSize = maxSize;
    this.maxFps = maxFps;
    _video = await Socket.connect(InternetAddress.loopbackIPv4, hostPort);
    connections++;
    _video!.add(
      videoBytes([
        sessionMeta(width: 540, height: 1170),
        videoPacket(config: true, bytes: [0, 0, 0, 1, 103]),
        videoPacket(key: true, bytes: [0, 0, 0, 1, 101]),
      ]),
    );
    await _video!.flush();
    return handle;
  }

  void sendVideo(List<List<int>> messages) {
    final bytes = BytesBuilder(copy: false);
    for (final message in messages) {
      bytes.add(message);
    }
    _video!.add(bytes.takeBytes());
  }
}
