import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:open_dex_api/open_dex_api.dart';
import 'package:open_dex_core/open_dex_core.dart';
import 'package:open_dex_platform/open_dex_platform.dart';
import 'package:test/test.dart';

import 'scrcpy_fakes.dart';

void main() {
  test(
    'launch overlaps app start and waits for the authoritative first frame',
    () async {
      final server = _FakeServerStarter();
      final decoders = FakeDecoderStarter();
      final textures = FakeTextureHost();
      final createdDisplays = <int>[];
      final gateway = DirectScrcpyWindowGateway(
        serverStarter: server,
        decoderStarter: decoders,
        serverJarPath: '/runtime/scrcpy-server',
        ffmpegExecutable: '/runtime/ffmpeg',
        textureHost: textures,
        processExecutor: const FakeExecutor(),
        surfaceRetireDelay: Duration.zero,
        onDisplayCreated: (_, displayId) async =>
            createdDisplays.add(displayId),
      );
      addTearDown(gateway.dispose);
      final firstFrame = Completer<void>();
      textures.frameGates[91] = firstFrame;

      final launch = gateway.launch(
        _device,
        _application,
        sessionId: 'direct-test-1',
      );
      await waitUntil(() => textures.waited.contains(91));
      expect(createdDisplays, [44]);
      expect(
        await server.firstControlMessage.timeout(const Duration(seconds: 1)),
        ScrcpyControlMessages.startApp(_application.packageName),
      );
      var launchCompleted = false;
      unawaited(launch.then((_) => launchCompleted = true));
      await Future<void>.delayed(Duration.zero);
      expect(launchCompleted, isFalse);
      firstFrame.complete();
      final session = await launch;

      expect(session.id, 'direct-test-1');
      expect(session.displayId, 44);
      expect(session.surface?.pixelSize.width, 832);
      expect(session.surface?.pixelSize.height, 1280);
      expect(textures.createdSizes.single.width, 832);
      expect(textures.createdSizes.single.height, 1280);
      expect(decoders.decoder.initialConfig?.isConfig, isTrue);
      expect(decoders.decoder.packets, hasLength(1));
      expect(decoders.decoder.packets.single.isKeyFrame, isTrue);
      expect(textures.waited, [91]);
      expect(
        await server.firstControlMessage,
        ScrcpyControlMessages.startApp(_application.packageName),
      );
    },
  );

  test(
    'resize waits for authoritative size and first replacement frame',
    () async {
      final server = _FakeServerStarter();
      final decoders = FakeDecoderStarter();
      final textures = FakeTextureHost();
      final gateway = DirectScrcpyWindowGateway(
        serverStarter: server,
        decoderStarter: decoders,
        serverJarPath: '/runtime/scrcpy-server',
        ffmpegExecutable: '/runtime/ffmpeg',
        textureHost: textures,
        processExecutor: const FakeExecutor(),
        surfaceRetireDelay: Duration.zero,
      );
      addTearDown(gateway.dispose);
      final original = await gateway.launch(_device, _application);
      final replacementFrame = Completer<void>();
      textures.frameGates[92] = replacementFrame;

      final resizedFuture = gateway.resizeSurface(
        original.id,
        const WindowPixelSize(width: 640, height: 1280),
      );
      await Future<void>.delayed(Duration.zero);
      server.sendVideo([
        sessionMeta(width: 656, height: 1280, clientResized: true),
        videoPacket(config: true, bytes: [0, 0, 0, 1, 103, 2]),
        videoPacket(key: true, bytes: [0, 0, 0, 1, 101, 2]),
      ]);
      await waitUntil(() => textures.waited.contains(92));
      var resizeCompleted = false;
      unawaited(resizedFuture.then((_) => resizeCompleted = true));
      await Future<void>.delayed(Duration.zero);
      expect(resizeCompleted, isFalse);
      replacementFrame.complete();
      final resized = await resizedFuture;
      await Future<void>.delayed(Duration.zero);

      expect(resized.displayId, original.displayId);
      expect(resized.surface?.pixelSize.width, 656);
      expect(resized.surface?.pixelSize.height, 1280);
      expect(resized.surface?.textureId, 92);
      expect(decoders.decoders, hasLength(2));
      expect(textures.waited, [91, 92]);
      expect(textures.closed, contains(91));
      expect(
        _containsSequence(
          server.controlBytes,
          ScrcpyControlMessages.resizeDisplay(640, 1280),
        ),
        isTrue,
      );
    },
  );

  test('app-forced rotation publishes a surface update', () async {
    final server = _FakeServerStarter();
    final gateway = DirectScrcpyWindowGateway(
      serverStarter: server,
      decoderStarter: FakeDecoderStarter(),
      serverJarPath: '/runtime/scrcpy-server',
      ffmpegExecutable: '/runtime/ffmpeg',
      textureHost: FakeTextureHost(),
      processExecutor: const FakeExecutor(),
      surfaceRetireDelay: Duration.zero,
    );
    addTearDown(gateway.dispose);
    await gateway.launch(_device, _application, sessionId: 'rotation');
    final update = gateway.surfaceUpdates.first;

    server.sendVideo([
      sessionMeta(width: 1280, height: 720),
      videoPacket(config: true, bytes: [0, 0, 0, 1, 103, 3]),
      videoPacket(key: true, bytes: [0, 0, 0, 1, 101, 3]),
    ]);

    expect(
      await update,
      isA<WindowBackendSession>()
          .having((value) => value.id, 'id', 'rotation')
          .having((value) => value.surface?.pixelSize.width, 'width', 1280)
          .having((value) => value.surface?.pixelSize.height, 'height', 720),
    );
  });

  test('server death publishes exit 21 and cleans the session', () async {
    final server = _FakeServerStarter();
    final textures = FakeTextureHost();
    final gateway = DirectScrcpyWindowGateway(
      serverStarter: server,
      decoderStarter: FakeDecoderStarter(),
      serverJarPath: '/runtime/scrcpy-server',
      ffmpegExecutable: '/runtime/ffmpeg',
      textureHost: textures,
      processExecutor: const FakeExecutor(),
      surfaceRetireDelay: Duration.zero,
    );
    addTearDown(gateway.dispose);
    final session = await gateway.launch(_device, _application);
    final exit = gateway.exits.first;

    server.handle.fail(7);

    expect(
      await exit,
      isA<WindowBackendExit>()
          .having((value) => value.sessionId, 'session', session.id)
          .having((value) => value.exitCode, 'code', 21),
    );
    expect(textures.closed, [91]);
  });

  test('decoder restarts once with CONFIG then publishes exit 22', () async {
    final server = _FakeServerStarter();
    final decoders = FakeDecoderStarter();
    final gateway = DirectScrcpyWindowGateway(
      serverStarter: server,
      decoderStarter: decoders,
      serverJarPath: '/runtime/scrcpy-server',
      ffmpegExecutable: '/runtime/ffmpeg',
      textureHost: FakeTextureHost(),
      processExecutor: const FakeExecutor(),
      surfaceRetireDelay: Duration.zero,
    );
    addTearDown(gateway.dispose);
    final session = await gateway.launch(_device, _application);

    decoders.decoders.first.fail(1);
    await waitUntil(
      () => decoders.decoders.length == 2 && server.controlBytes.contains(17),
    );
    expect(decoders.decoders.last.initialConfig?.isConfig, isTrue);
    expect(server.controlBytes, contains(17));
    final exit = gateway.exits.first;
    decoders.decoders.last.fail(1);

    expect(
      await exit,
      isA<WindowBackendExit>()
          .having((value) => value.sessionId, 'session', session.id)
          .having((value) => value.exitCode, 'code', 22),
    );
  });

  test('routes touch, text, and key up/down over the control socket', () async {
    final server = _FakeServerStarter();
    final gateway = DirectScrcpyWindowGateway(
      serverStarter: server,
      decoderStarter: FakeDecoderStarter(),
      serverJarPath: '/runtime/scrcpy-server',
      ffmpegExecutable: '/runtime/ffmpeg',
      textureHost: FakeTextureHost(),
      processExecutor: const FakeExecutor(),
      surfaceRetireDelay: Duration.zero,
    );
    addTearDown(gateway.dispose);
    final session = await gateway.launch(_device, _application);
    await server.firstControlMessage;
    await waitUntil(
      () =>
          server.controlBytes.length >=
          ScrcpyControlMessages.startApp(_application.packageName).length,
    );
    final offset = server.controlBytes.length;

    await gateway.sendPointer(
      session.id,
      const WindowPointerSample(
        phase: WindowPointerPhase.down,
        x: 12.4,
        y: 25.6,
        pointerId: 7,
      ),
    );
    await gateway.sendKey(
      session.id,
      const WindowKeySample(
        phase: WindowKeyPhase.down,
        physicalKeyId: 0,
        logicalKeyId: 0,
        character: 'a',
      ),
    );
    await gateway.sendKey(
      session.id,
      const WindowKeySample(
        phase: WindowKeyPhase.down,
        physicalKeyId: 0x00070028,
        logicalKeyId: 0,
      ),
    );
    await gateway.sendKey(
      session.id,
      const WindowKeySample(
        phase: WindowKeyPhase.up,
        physicalKeyId: 0x00070028,
        logicalKeyId: 0,
      ),
    );
    await waitUntil(() => server.controlBytes.length >= offset + 66);

    expect(server.controlBytes.sublist(offset), [
      ...ScrcpyControlMessages.injectTouch(
        action: ScrcpyTouchAction.down,
        x: 12,
        y: 26,
        screenWidth: 832,
        screenHeight: 1280,
      ),
      ...ScrcpyControlMessages.injectText('a'),
      ...ScrcpyControlMessages.injectKey(
        action: ScrcpyKeyAction.down,
        keycode: 66,
      ),
      ...ScrcpyControlMessages.injectKey(
        action: ScrcpyKeyAction.up,
        keycode: 66,
      ),
    ]);
  });

  test('close stops decoder, texture, sockets, and server handle', () async {
    final server = _FakeServerStarter();
    final decoders = FakeDecoderStarter();
    final textures = FakeTextureHost();
    final gateway = DirectScrcpyWindowGateway(
      serverStarter: server,
      decoderStarter: decoders,
      serverJarPath: '/runtime/scrcpy-server',
      ffmpegExecutable: '/runtime/ffmpeg',
      textureHost: textures,
      processExecutor: const FakeExecutor(),
      surfaceRetireDelay: Duration.zero,
    );
    addTearDown(gateway.dispose);
    final session = await gateway.launch(_device, _application);

    await gateway.close(session.id);

    expect(decoders.decoders.single.stopped, isTrue);
    expect(textures.closed, [91]);
    expect(server.handle.stopped, isTrue);
  });

  test('telemetry separates produced, presented, and dropped rates', () async {
    final textures = FakeTextureHost();
    final gateway = DirectScrcpyWindowGateway(
      serverStarter: _FakeServerStarter(),
      decoderStarter: FakeDecoderStarter(),
      serverJarPath: '/runtime/scrcpy-server',
      ffmpegExecutable: '/runtime/ffmpeg',
      textureHost: textures,
      processExecutor: const FakeExecutor(),
      telemetryInterval: const Duration(milliseconds: 1),
      surfaceRetireDelay: Duration.zero,
    );
    addTearDown(gateway.dispose);
    await gateway.launch(_device, _application);
    textures
      ..frames = 12
      ..presentedFrames = 9
      ..droppedFrames = 3;

    final sample = await gateway.telemetry.first.timeout(
      const Duration(seconds: 1),
    );

    expect(sample.producedFramesPerSecond, greaterThan(0));
    expect(sample.presentedFramesPerSecond, greaterThan(0));
    expect(sample.droppedFramesPerSecond, greaterThan(0));
    expect(
      sample.producedFramesPerSecond,
      greaterThan(sample.presentedFramesPerSecond!),
    );
  });

  test('a portrait phone gets a portrait display request', () async {
    final server = _FakeServerStarter();
    final decoders = FakeDecoderStarter();
    final textures = FakeTextureHost();
    final gateway = DirectScrcpyWindowGateway(
      serverStarter: server,
      decoderStarter: decoders,
      serverJarPath: '/runtime/scrcpy-server',
      ffmpegExecutable: '/runtime/ffmpeg',
      textureHost: textures,
      processExecutor: const FakeExecutor(),
      surfaceRetireDelay: Duration.zero,
      // A portrait-natural phone. The display must be created portrait so the
      // launcher and portrait apps start upright rather than rotated 90°.
      adb: _FakeAdb('Physical size: 1080x2340'),
    );
    addTearDown(gateway.dispose);
    final firstFrame = Completer<void>();
    textures.frameGates[91] = firstFrame;

    final launch = gateway.launch(_device, _application, sessionId: 'ori-1');
    await waitUntil(() => textures.waited.contains(91));
    firstFrame.complete();
    await launch;

    expect(server.capturedDisplaySize!.height, 1280);
    expect(server.capturedDisplaySize!.width, 720);
    expect(
      server.capturedDisplaySize!.height,
      greaterThan(server.capturedDisplaySize!.width),
      reason: 'a portrait phone must get a portrait display',
    );
  });

  test('a landscape-natural device gets a landscape display request', () async {
    final server = _FakeServerStarter();
    final decoders = FakeDecoderStarter();
    final textures = FakeTextureHost();
    final gateway = DirectScrcpyWindowGateway(
      serverStarter: server,
      decoderStarter: decoders,
      serverJarPath: '/runtime/scrcpy-server',
      ffmpegExecutable: '/runtime/ffmpeg',
      textureHost: textures,
      processExecutor: const FakeExecutor(),
      surfaceRetireDelay: Duration.zero,
      adb: _FakeAdb('Physical size: 1920x1080'),
    );
    addTearDown(gateway.dispose);
    final firstFrame = Completer<void>();
    textures.frameGates[91] = firstFrame;

    final launch = gateway.launch(_device, _application, sessionId: 'ori-2');
    await waitUntil(() => textures.waited.contains(91));
    firstFrame.complete();
    await launch;

    expect(
      server.capturedDisplaySize!.width,
      greaterThan(server.capturedDisplaySize!.height),
      reason: 'a landscape device must get a landscape display',
    );
  });

  test('without adb, the display falls back to the default size', () async {
    final server = _FakeServerStarter();
    final decoders = FakeDecoderStarter();
    final textures = FakeTextureHost();
    final gateway = DirectScrcpyWindowGateway(
      serverStarter: server,
      decoderStarter: decoders,
      serverJarPath: '/runtime/scrcpy-server',
      ffmpegExecutable: '/runtime/ffmpeg',
      textureHost: textures,
      processExecutor: const FakeExecutor(),
      surfaceRetireDelay: Duration.zero,
      initialPixelSize: const WindowPixelSize(width: 1280, height: 896),
      // No adb: orientation cannot be read, so the default stands.
    );
    addTearDown(gateway.dispose);
    final firstFrame = Completer<void>();
    textures.frameGates[91] = firstFrame;

    final launch = gateway.launch(_device, _application, sessionId: 'ori-3');
    await waitUntil(() => textures.waited.contains(91));
    firstFrame.complete();
    await launch;

    expect(server.capturedDisplaySize!.width, 1280);
    expect(server.capturedDisplaySize!.height, 896);
  });

  test(
    'backspace and Ctrl+C are sent as keycodes, plain text as text',
    () async {
      final server = _FakeServerStarter();
      final decoders = FakeDecoderStarter();
      final textures = FakeTextureHost();
      final gateway = DirectScrcpyWindowGateway(
        serverStarter: server,
        decoderStarter: decoders,
        serverJarPath: '/runtime/scrcpy-server',
        ffmpegExecutable: '/runtime/ffmpeg',
        textureHost: textures,
        processExecutor: const FakeExecutor(),
        surfaceRetireDelay: Duration.zero,
      );
      addTearDown(gateway.dispose);
      final launched = await gateway.launch(_device, _application);
      await server.firstControlMessage;
      final String sid = launched.id;

      Future<List<int>> delta(Future<void> Function() act) async {
        final int before = server.controlBytes.length;
        await act();
        await waitUntil(() => server.controlBytes.length > before);
        return server.controlBytes.sublist(before);
      }

      // Backspace: character is the control code U+0008, but it must land as a
      // KEYCODE_DEL (67) keycode, not as typed text.
      final List<int> back = await delta(
        () => gateway.sendKey(
          sid,
          const WindowKeySample(
            phase: WindowKeyPhase.down,
            physicalKeyId: 0x0007002a,
            logicalKeyId: 0,
            character: '\b',
          ),
        ),
      );
      expect(
        back,
        ScrcpyControlMessages.injectKey(
          action: ScrcpyKeyAction.down,
          keycode: 67,
        ),
        reason: 'backspace must be a keycode, not injected text',
      );

      // Ctrl+C: a letter, but with Ctrl held it is a command — a KEYCODE_C (31)
      // with the CTRL meta bit, not the character c.
      final List<int> copy = await delta(
        () => gateway.sendKey(
          sid,
          const WindowKeySample(
            phase: WindowKeyPhase.down,
            physicalKeyId: 0x00070006,
            logicalKeyId: 0,
            character: 'c',
            ctrl: true,
          ),
        ),
      );
      expect(
        copy,
        ScrcpyControlMessages.injectKey(
          action: ScrcpyKeyAction.down,
          keycode: 31,
          metaState: 0x1000,
        ),
        reason: 'Ctrl+C must carry the CTRL meta bit as a keycode',
      );

      // A plain letter with no modifier is typed text (INJECT_TEXT, type 1).
      final List<int> typed = await delta(
        () => gateway.sendKey(
          sid,
          const WindowKeySample(
            phase: WindowKeyPhase.down,
            physicalKeyId: 0x00070007,
            logicalKeyId: 0,
            character: 'd',
          ),
        ),
      );
      expect(typed.first, 1, reason: 'plain text uses INJECT_TEXT (type 1)');
    },
  );

  test('right-click sends Android Back, not a touch', () async {
    final server = _FakeServerStarter();
    final decoders = FakeDecoderStarter();
    final textures = FakeTextureHost();
    final gateway = DirectScrcpyWindowGateway(
      serverStarter: server,
      decoderStarter: decoders,
      serverJarPath: '/runtime/scrcpy-server',
      ffmpegExecutable: '/runtime/ffmpeg',
      textureHost: textures,
      processExecutor: const FakeExecutor(),
      surfaceRetireDelay: Duration.zero,
    );
    addTearDown(gateway.dispose);
    final launched = await gateway.launch(_device, _application);
    await server.firstControlMessage;
    final String sid = launched.id;

    Future<List<int>> delta(Future<void> Function() act) async {
      final int before = server.controlBytes.length;
      await act();
      await waitUntil(() => server.controlBytes.length > before);
      return server.controlBytes.sublist(before);
    }

    // Right-press: one Back keycode down, then up. No touch.
    final List<int> press = await delta(
      () => gateway.sendPointer(
        sid,
        const WindowPointerSample(
          phase: WindowPointerPhase.down,
          x: 40,
          y: 60,
          pointerId: 7,
          buttons: 0x02,
        ),
      ),
    );
    expect(press, <int>[
      ...ScrcpyControlMessages.injectKey(
        action: ScrcpyKeyAction.down,
        keycode: 4,
      ),
      ...ScrcpyControlMessages.injectKey(
        action: ScrcpyKeyAction.up,
        keycode: 4,
      ),
    ], reason: 'right-click is Back down+up, no INJECT_TOUCH');

    // The release of that same right gesture is swallowed — no bytes at all.
    final int before = server.controlBytes.length;
    await gateway.sendPointer(
      sid,
      const WindowPointerSample(
        phase: WindowPointerPhase.up,
        x: 40,
        y: 60,
        pointerId: 7,
      ),
    );
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(
      server.controlBytes.length,
      before,
      reason: 'right release is swallowed',
    );
  });
}

/// An [AdbClient] whose `shell` always returns [_output], for `wm size`.
class _FakeAdb extends AdbClient {
  _FakeAdb(this._output);

  final String _output;

  @override
  Future<String> shell(String deviceId, List<String> command) async => _output;
}

const _device = DeviceSummary(
  id: 'device-1',
  name: 'Phone',
  connectionKind: DeviceConnectionKind.usb,
  status: DeviceStatus.authorized,
);
const _application = AndroidApplication(
  packageName: 'com.example.app',
  label: 'Example',
);

class _FakeServerStarter implements ScrcpyServerStarter {
  final _controlBytes = Completer<List<int>>();
  final _handle = FakeServerHandle();
  Socket? _video;
  Socket? _control;
  final controlBytes = <int>[];

  /// The size the gateway asked the server to create the display at.
  WindowPixelSize? capturedDisplaySize;

  Future<List<int>> get firstControlMessage => _controlBytes.future;

  FakeServerHandle get handle => _handle;

  @override
  Future<ScrcpyServerSession> start({
    required DeviceSummary device,
    required String serverJarPath,
    required int hostPort,
    required String scid,
    required WindowPixelSize displaySize,
    required int dpi,
    String? encoder,
    Duration displayTimeout = const Duration(seconds: 5),
  }) async {
    capturedDisplaySize = displaySize;
    _video = await Socket.connect(InternetAddress.loopbackIPv4, hostPort);
    _control = await Socket.connect(InternetAddress.loopbackIPv4, hostPort);
    _control!.listen((bytes) {
      controlBytes.addAll(bytes);
      if (!_controlBytes.isCompleted) {
        _controlBytes.complete(List<int>.from(bytes));
      }
    });
    _video!.add(
      videoBytes([
        sessionMeta(width: 832, height: 1280),
        videoPacket(config: true, bytes: [0, 0, 0, 1, 103]),
        videoPacket(key: true, bytes: [0, 0, 0, 1, 101]),
      ]),
    );
    await _video!.flush();
    return _handle;
  }

  void sendVideo(List<List<int>> messages) {
    final bytes = BytesBuilder(copy: false);
    for (final message in messages) {
      bytes.add(message);
    }
    _video!.add(bytes.takeBytes());
  }
}

bool _containsSequence(List<int> source, List<int> pattern) {
  for (var start = 0; start + pattern.length <= source.length; start++) {
    var matches = true;
    for (var offset = 0; offset < pattern.length; offset++) {
      if (source[start + offset] != pattern[offset]) {
        matches = false;
        break;
      }
    }
    if (matches) return true;
  }
  return false;
}
