import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:open_dex_api/open_dex_api.dart';
import 'package:open_dex_core/open_dex_core.dart';

import '../process_executor.dart';
import '../adb_client.dart';
import 'display_orientation.dart';
import 'h264_decoder_process.dart';
import 'scrcpy_control_channel.dart';
import 'scrcpy_control_messages.dart';
import 'scrcpy_frames.dart';
import 'scrcpy_server_launcher.dart';
import 'scrcpy_video_stream.dart';

class DirectScrcpyWindowGateway
    implements
        WindowGateway,
        ResizableWindowGateway,
        WindowSurfaceUpdateGateway,
        NavKeyWindowGateway {
  DirectScrcpyWindowGateway({
    required this.serverStarter,
    required this.decoderStarter,
    required this.serverJarPath,
    required this.ffmpegExecutable,
    required this.textureHost,
    this.adb,
    this.processExecutor = const SystemProcessExecutor(),
    this.startTimeout = const Duration(seconds: 15),
    this.firstFrameTimeout = const Duration(seconds: 10),
    this.surfaceRetireDelay = const Duration(milliseconds: 250),
    this.telemetryInterval = const Duration(seconds: 1),
    this.initialPixelSize = const WindowPixelSize(width: 1280, height: 896),
    this.dpi = 240,
    this.onClipboard,
    this.onDisplayCreated,
  }) {
    if (startTimeout <= Duration.zero || firstFrameTimeout <= Duration.zero) {
      throw ArgumentError('Direct stream timeouts must be greater than zero.');
    }
    if (surfaceRetireDelay.isNegative || telemetryInterval <= Duration.zero) {
      throw ArgumentError('Direct stream intervals are invalid.');
    }
    if (dpi < 1 || dpi > 65535) {
      throw ArgumentError.value(dpi, 'dpi', 'must fit unsigned 16-bit');
    }
  }

  final ScrcpyServerStarter serverStarter;
  final H264DecoderStarter decoderStarter;
  final String serverJarPath;
  final String ffmpegExecutable;
  final WindowTextureHost textureHost;

  /// Used once per device to read the phone's natural orientation, so the
  /// initial display is created upright rather than rotated. Optional: without
  /// it the gateway falls back to [initialPixelSize].
  final AdbClient? adb;
  final ProcessExecutor processExecutor;
  final Duration startTimeout;
  final Duration firstFrameTimeout;
  final Duration surfaceRetireDelay;
  final Duration telemetryInterval;
  final WindowPixelSize initialPixelSize;
  final int dpi;
  final void Function(String text)? onClipboard;
  final Future<void> Function(DeviceSummary device, int displayId)?
  onDisplayCreated;

  final StreamController<WindowBackendExit> _exits =
      StreamController<WindowBackendExit>.broadcast(sync: true);
  final StreamController<WindowBackendTelemetry> _telemetry =
      StreamController<WindowBackendTelemetry>.broadcast(sync: true);
  final StreamController<WindowBackendSession> _surfaceUpdates =
      StreamController<WindowBackendSession>.broadcast(sync: true);
  final Map<String, _DirectSession> _sessions = {};
  final Set<Future<void>> _retirements = {};
  final Random _random = Random.secure();
  var _sequence = 0;

  @override
  Stream<WindowBackendExit> get exits => _exits.stream;

  @override
  Stream<WindowBackendTelemetry> get telemetry => _telemetry.stream;

  @override
  Stream<WindowBackendSession> get surfaceUpdates => _surfaceUpdates.stream;

  @override
  Future<WindowBackendSession> launch(
    DeviceSummary device,
    AndroidApplication application, {
    String? sessionId,
  }) async {
    _validate(device, application);
    final resolvedId =
        sessionId ??
        'direct-${DateTime.now().toUtc().microsecondsSinceEpoch.toRadixString(36)}-${++_sequence}';
    if (_sessions.containsKey(resolvedId)) throw _closedFailure();

    ServerSocket? listener;
    StreamIterator<Socket>? accepts;
    ScrcpyServerSession? server;
    Socket? videoSocket;
    Socket? controlSocket;
    ScrcpyVideoStream? video;
    StreamIterator<ScrcpyVideoEvent>? events;
    ScrcpyControlChannel? control;
    _DecoderSurface? surface;
    try {
      listener = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      accepts = StreamIterator<Socket>(listener);
      server = await serverStarter.start(
        device: device,
        serverJarPath: serverJarPath,
        hostPort: listener.port,
        scid: _newScid(),
        displaySize: await _initialSizeFor(device),
        dpi: dpi,
      );
      if (!await accepts.moveNext().timeout(startTimeout)) {
        throw TimeoutException('The scrcpy video socket did not connect.');
      }
      videoSocket = accepts.current;
      if (!await accepts.moveNext().timeout(startTimeout)) {
        throw TimeoutException('The scrcpy control socket did not connect.');
      }
      controlSocket = accepts.current;
      await accepts.cancel();
      accepts = null;
      await listener.close();
      listener = null;

      video = ScrcpyVideoStream(videoSocket);
      events = StreamIterator<ScrcpyVideoEvent>(video.events);
      control = ScrcpyControlChannel(controlSocket, onClipboard: onClipboard);
      await video.deviceName.timeout(startTimeout);
      final codec = await video.codecId.timeout(startTimeout);
      if (codec != 0x68323634) {
        throw BackendFailure(
          OpenDexError(
            code: OpenDexErrorCode.capabilityUnavailable,
            message: 'scrcpy-server selected an unsupported video codec.',
            retryable: false,
            capability: 'application-streaming',
            technicalDetails: 'codec=0x${codec.toRadixString(16)}',
          ),
        );
      }
      final meta = await _nextSessionMeta(events).timeout(startTimeout);
      await control.startApp(application.packageName);
      final displayId = await server.displayId.timeout(startTimeout);
      await onDisplayCreated?.call(device, displayId);
      final configured = await _nextConfiguredSession(
        events,
        meta,
      ).timeout(startTimeout);
      final config = configured.config;
      surface = await _startDecoderSurface(
        configured.meta.pixelSize,
        config,
        control,
      );

      // Feed the decoder continuously while waiting for its first frame.
      //
      // A software H.264 decoder does not emit frame N until frame N+1 arrives
      // — ordinary decode latency. The old code fed up to the first key frame,
      // then stopped and waited: the key frame sat undecoded, the wait timed
      // out, and ffmpeg printed nothing because it was simply blocked reading
      // more input. The legacy pipeline never saw this because it read a
      // continuous MKV stream; the direct feed has to keep the packets coming
      // or it starves the very frame it is waiting for.
      final Future<void> firstFrame = textureHost.waitForFirstFrame(
        surface.textureId,
        timeout: firstFrameTimeout,
      );
      var firstFrameSettled = false;
      unawaited(
        firstFrame.then<void>(
          (_) => firstFrameSettled = true,
          onError: (Object _, StackTrace _) {
            // The original future is awaited below and reports the launch
            // failure. Do not create a second unhandled failure while observing
            // its completion.
            firstFrameSettled = true;
          },
        ),
      );
      var sawKeyFrame = false;
      while (!firstFrameSettled) {
        final bool hasEvent;
        try {
          hasEvent = await events.moveNext().timeout(startTimeout);
        } on TimeoutException {
          // No more packets arriving. Let the first-frame wait be the arbiter
          // of success or failure rather than failing on the input gap.
          break;
        }
        if (!hasEvent) break;
        final event = events.current;
        if (event is ScrcpyVideoPacket) {
          surface.decoder.feed(event);
          sawKeyFrame = sawKeyFrame || event.isKeyFrame;
        }
      }
      // Propagates the first-frame timeout as the launch failure when it fired.
      // The decoder has now been fed continuously, so a failure here is a real
      // decode failure and its stderr tail is attached below — not a starvation
      // artifact of our own making.
      await firstFrame;
      if (!sawKeyFrame) {
        throw const ScrcpyVideoStreamException(
          'The scrcpy video stream ended before its first key frame.',
        );
      }
      final directSession = _DirectSession(
        id: resolvedId,
        application: application,
        displayId: displayId,
        server: server,
        videoSocket: videoSocket,
        controlSocket: controlSocket,
        video: video,
        events: events,
        control: control,
        surface: surface,
        latestConfig: config,
      );
      _sessions[resolvedId] = directSession;
      _watchSession(directSession);
      _watchDecoder(directSession, surface);
      unawaited(_consumeVideo(directSession));
      _startTelemetry(directSession);
      return WindowBackendSession(
        id: resolvedId,
        displayId: displayId,
        surface: surface.windowSurface,
      );
    } on BackendFailure {
      await _cleanupPartial(
        listener: listener,
        accepts: accepts,
        server: server,
        videoSocket: videoSocket,
        controlSocket: controlSocket,
        video: video,
        events: events,
        control: control,
        surface: surface,
      );
      rethrow;
    } on Object catch (error) {
      await _cleanupPartial(
        listener: listener,
        accepts: accepts,
        server: server,
        videoSocket: videoSocket,
        controlSocket: controlSocket,
        video: video,
        events: events,
        control: control,
        surface: surface,
      );
      final List<String> decoderOutput =
          surface?.decoder.outputTail ?? const <String>[];
      throw _failure(
        'The direct Android application stream could not start.',
        error,
        // The decoder's own account of the failure, when it gave one. A
        // first-frame timeout says only that no frame arrived; FFmpeg usually
        // knows why and until now nothing was reading what it said.
        decoderOutput,
      );
    }
  }

  Future<_DecoderSurface> _startDecoderSurface(
    WindowPixelSize size,
    ScrcpyVideoPacket config,
    ScrcpyControlChannel control,
  ) async {
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
        throw _failure('The direct decoder frame pipe could not be created.');
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
        resetVideo: control.resetVideo,
      );
      return _DecoderSurface(
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

  Future<ScrcpySessionMeta> _nextSessionMeta(
    StreamIterator<ScrcpyVideoEvent> events,
  ) async {
    while (await events.moveNext()) {
      final event = events.current;
      if (event is ScrcpySessionMeta) return event;
    }
    throw const ScrcpyVideoStreamException(
      'The scrcpy video stream ended before session metadata.',
    );
  }

  Future<({ScrcpySessionMeta meta, ScrcpyVideoPacket config})>
  _nextConfiguredSession(
    StreamIterator<ScrcpyVideoEvent> events,
    ScrcpySessionMeta initialMeta,
  ) async {
    var meta = initialMeta;
    while (await events.moveNext()) {
      final event = events.current;
      if (event is ScrcpySessionMeta) {
        meta = event;
      } else if (event is ScrcpyVideoPacket && event.isConfig) {
        return (meta: meta, config: event);
      }
    }
    throw const ScrcpyVideoStreamException(
      'The scrcpy video stream ended before decoder configuration.',
    );
  }

  Future<void> _consumeVideo(_DirectSession session) async {
    try {
      while (!session.closed && await session.events.moveNext()) {
        final event = session.events.current;
        if (event is ScrcpySessionMeta) {
          session.pendingMeta = event;
          continue;
        }
        if (event is! ScrcpyVideoPacket) continue;
        if (event.isConfig) {
          session.latestConfig = event;
          final meta = session.pendingMeta;
          if (meta != null) {
            session.pendingMeta = null;
            await _prepareReplacement(session, meta, event);
          } else {
            session.surface.decoder.feed(event);
          }
          continue;
        }
        final replacement = session.replacement;
        if (replacement == null) {
          session.surface.decoder.feed(event);
          continue;
        }
        replacement.decoder.feed(event);
        if (event.isKeyFrame && !session.replacementActivating) {
          session.replacementActivating = true;
          unawaited(_activateReplacement(session, replacement));
        }
      }
      if (!session.closed) await _unexpectedExit(session, 21);
    } on Object {
      if (!session.closed) await _unexpectedExit(session, 21);
    }
  }

  Future<void> _prepareReplacement(
    _DirectSession session,
    ScrcpySessionMeta meta,
    ScrcpyVideoPacket config,
  ) async {
    final size = meta.pixelSize;
    if (_sameSize(size, session.surface.pixelSize)) {
      session.surface.decoder.feed(config);
      _completeResize(session);
      return;
    }
    final stale = session.replacement;
    session.replacement = null;
    session.replacementActivating = false;
    if (stale != null) await stale.dispose(textureHost);
    final replacement = await _startDecoderSurface(
      size,
      config,
      session.control,
    );
    if (session.closed) {
      await replacement.dispose(textureHost);
      return;
    }
    session.replacement = replacement;
    _watchDecoder(session, replacement);
  }

  Future<void> _activateReplacement(
    _DirectSession session,
    _DecoderSurface replacement,
  ) async {
    try {
      await textureHost.waitForFirstFrame(
        replacement.textureId,
        timeout: firstFrameTimeout,
      );
      if (session.closed) return;
      if (!identical(session.replacement, replacement)) {
        await replacement.dispose(textureHost);
        return;
      }
      final old = session.surface;
      session.surface = replacement;
      session.replacement = null;
      session.replacementActivating = false;
      _completeResize(session);
      if (!_surfaceUpdates.isClosed) {
        _surfaceUpdates.add(session.backendSession);
      }
      final retirement = Future<void>.delayed(
        surfaceRetireDelay,
        () => old.dispose(textureHost),
      );
      _retirements.add(retirement);
      unawaited(retirement.whenComplete(() => _retirements.remove(retirement)));
    } on Object catch (error, stackTrace) {
      if (session.closed) return;
      if (identical(session.replacement, replacement)) {
        session.replacement = null;
        session.replacementActivating = false;
      }
      await replacement.dispose(textureHost);
      final completion = session.resizeCompletion;
      session.resizeCompletion = null;
      if (completion != null && !completion.isCompleted) {
        completion.completeError(error, stackTrace);
      }
    }
  }

  void _completeResize(_DirectSession session) {
    final completion = session.resizeCompletion;
    session.resizeCompletion = null;
    if (completion != null && !completion.isCompleted) {
      completion.complete(session.backendSession);
    }
  }

  void _watchSession(_DirectSession session) {
    unawaited(
      session.server.exitCode.then((_) {
        if (!session.closed) return _unexpectedExit(session, 21);
      }),
    );
  }

  void _watchDecoder(_DirectSession session, _DecoderSurface surface) {
    final watched = surface.decoder;
    unawaited(
      watched.exitCode.then(
        (code) => _handleDecoderExit(session, surface, watched, code),
      ),
    );
  }

  Future<void> _handleDecoderExit(
    _DirectSession session,
    _DecoderSurface surface,
    H264Decoder watched,
    int _,
  ) async {
    if (session.closed || !identical(surface.decoder, watched)) return;
    final owned =
        identical(session.surface, surface) ||
        identical(session.replacement, surface);
    if (!owned) return;
    if (surface.restartCount >= 1) {
      await _unexpectedExit(session, 22);
      return;
    }
    surface.restartCount += 1;
    try {
      final decoder = await decoderStarter.start(
        ffmpegPath: ffmpegExecutable,
        fifoPath: surface.fifoPath,
        latestConfig: session.latestConfig,
        resetVideo: session.control.resetVideo,
      );
      if (session.closed) {
        await decoder.stop();
        return;
      }
      surface.decoder = decoder;
      _watchDecoder(session, surface);
      await session.control.resetVideo();
    } on Object {
      await _unexpectedExit(session, 22);
    }
  }

  void _startTelemetry(_DirectSession session) {
    var previousFrames = 0;
    var previousPresented = 0;
    var previousDropped = 0;
    var previousTexture = session.surface.textureId;
    var previousTime = DateTime.now();
    session.telemetryTimer = Timer.periodic(telemetryInterval, (_) async {
      if (session.closed || _telemetry.isClosed) return;
      try {
        final stats = await textureHost.stats(session.surface.textureId);
        final now = DateTime.now();
        final textureId = session.surface.textureId;
        if (textureId != previousTexture) {
          previousTexture = textureId;
          previousFrames = stats.frames;
          previousPresented = stats.presentedFrames;
          previousDropped = stats.droppedFrames;
          previousTime = now;
          return;
        }
        final elapsed = now.difference(previousTime).inMicroseconds / 1000000;
        final produced = elapsed <= 0
            ? 0.0
            : (stats.frames - previousFrames) / elapsed;
        final presented = elapsed <= 0
            ? 0.0
            : (stats.presentedFrames - previousPresented) / elapsed;
        final dropped = elapsed <= 0
            ? 0.0
            : (stats.droppedFrames - previousDropped) / elapsed;
        previousFrames = stats.frames;
        previousPresented = stats.presentedFrames;
        previousDropped = stats.droppedFrames;
        previousTime = now;
        if (!_telemetry.isClosed) {
          _telemetry.add(
            WindowBackendTelemetry(
              sessionId: session.id,
              producedFramesPerSecond: produced,
              presentedFramesPerSecond: presented,
              droppedFramesPerSecond: dropped,
            ),
          );
        }
      } on Object {
        // A surface swap or close may retire the sampled texture.
      }
    });
  }

  Future<void> _unexpectedExit(_DirectSession session, int exitCode) async {
    if (_sessions.remove(session.id) == null) return;
    await _disposeSession(session);
    if (!_exits.isClosed) {
      _exits.add(
        WindowBackendExit(
          sessionId: session.id,
          exitCode: exitCode,
          details: exitCode == 21 && session.server.stderrTail.isNotEmpty
              ? session.server.stderrTail.join(' | ')
              : 'direct window backend exit code $exitCode',
        ),
      );
    }
  }

  @override
  Future<void> close(String sessionId) async {
    final session = _sessions.remove(sessionId);
    if (session == null) return;
    await _disposeSession(session);
  }

  Future<void> _disposeSession(_DirectSession session) async {
    if (session.closed) return;
    session.closed = true;
    session.telemetryTimer?.cancel();
    final resize = session.resizeCompletion;
    session.resizeCompletion = null;
    if (resize != null && !resize.isCompleted) {
      resize.complete(session.backendSession);
    }
    await _bestEffort(session.events.cancel);
    await _bestEffort(session.control.close);
    await _bestEffort(session.video.dispose);
    await _bestEffort(session.videoSocket.close);
    await _bestEffort(session.controlSocket.close);
    await _bestEffort(() => session.surface.dispose(textureHost));
    final replacement = session.replacement;
    session.replacement = null;
    if (replacement != null) {
      await _bestEffort(() => replacement.dispose(textureHost));
    }
    await _bestEffort(session.server.stop);
  }

  Future<void> _cleanupPartial({
    required ServerSocket? listener,
    required StreamIterator<Socket>? accepts,
    required ScrcpyServerSession? server,
    required Socket? videoSocket,
    required Socket? controlSocket,
    required ScrcpyVideoStream? video,
    required StreamIterator<ScrcpyVideoEvent>? events,
    required ScrcpyControlChannel? control,
    required _DecoderSurface? surface,
  }) async {
    if (accepts != null) await _bestEffort(accepts.cancel);
    if (events != null) await _bestEffort(events.cancel);
    if (control != null) await _bestEffort(control.close);
    if (video != null) await _bestEffort(video.dispose);
    if (videoSocket != null) await _bestEffort(videoSocket.close);
    if (controlSocket != null) await _bestEffort(controlSocket.close);
    if (surface != null) {
      await _bestEffort(() => surface.dispose(textureHost));
    }
    if (server != null) await _bestEffort(server.stop);
    if (listener != null) await _bestEffort(listener.close);
  }

  @override
  Future<void> sendPointer(String sessionId, WindowPointerSample sample) async {
    final session = _sessions[sessionId];
    if (session == null) throw _closedFailure();
    final size = session.surface.pixelSize;
    final x = sample.x.round().clamp(0, size.width - 1);
    final y = sample.y.round().clamp(0, size.height - 1);

    // Right-click is Android Back, not a tap — the way scrcpy's own client maps
    // the secondary mouse button. A right-press sends BACK once; the rest of the
    // gesture (its move and release) is swallowed so it never lands as a stray
    // touch, tracked by pointer id so a normal finger is unaffected.
    const int secondaryButton = 0x02;
    if (sample.phase == WindowPointerPhase.down &&
        (sample.buttons & secondaryButton) != 0) {
      session.secondaryPointers.add(sample.pointerId);
      await session.control.injectKey(
        action: ScrcpyKeyAction.down,
        keycode: _androidBack,
      );
      await session.control.injectKey(
        action: ScrcpyKeyAction.up,
        keycode: _androidBack,
      );
      return;
    }
    if (session.secondaryPointers.contains(sample.pointerId)) {
      if (sample.phase == WindowPointerPhase.up ||
          sample.phase == WindowPointerPhase.cancel) {
        session.secondaryPointers.remove(sample.pointerId);
      }
      return;
    }

    if (sample.phase == WindowPointerPhase.scroll) {
      await session.control.injectScroll(
        x: x,
        y: y,
        screenWidth: size.width,
        screenHeight: size.height,
        horizontal: sample.scrollDeltaX,
        vertical: sample.scrollDeltaY,
      );
      return;
    }
    await session.control.injectTouch(
      action: switch (sample.phase) {
        WindowPointerPhase.down => ScrcpyTouchAction.down,
        WindowPointerPhase.move => ScrcpyTouchAction.move,
        WindowPointerPhase.up => ScrcpyTouchAction.up,
        WindowPointerPhase.cancel => ScrcpyTouchAction.cancel,
        WindowPointerPhase.scroll => throw StateError('handled above'),
      },
      x: x,
      y: y,
      screenWidth: size.width,
      screenHeight: size.height,
    );
  }

  @override
  Future<void> sendKey(String sessionId, WindowKeySample sample) async {
    final session = _sessions[sessionId];
    if (session == null) throw _closedFailure();
    final String? character = sample.character;
    // Send as typed text only when it is genuinely printable text and no
    // command modifier is held. `event.character` is non-empty even for
    // Backspace (U+0008), Enter, Tab and Escape — routing those to injectText
    // typed a control character that did nothing, which is why Backspace
    // appeared dead. And a Ctrl/Alt/Meta combination is a command (Ctrl+C), not
    // text, so it must go as a keycode with meta-state even when it is a letter.
    final bool command = sample.ctrl || sample.alt || sample.meta;
    if (!command &&
        character != null &&
        character.isNotEmpty &&
        _isPrintable(character)) {
      if (sample.phase == WindowKeyPhase.down) {
        await session.control.injectText(character);
      }
      return;
    }
    final int? keycode = _androidKeyCode(sample.physicalKeyId);
    if (keycode == null) return;
    await session.control.injectKey(
      action: sample.phase == WindowKeyPhase.down
          ? ScrcpyKeyAction.down
          : ScrcpyKeyAction.up,
      keycode: keycode,
      repeat: sample.repeat ? 1 : 0,
      metaState: _metaState(sample),
    );
  }

  @override
  Future<void> sendNavKey(String sessionId, AndroidNavKey key) async {
    final session = _sessions[sessionId];
    if (session == null) throw _closedFailure();
    final int keycode = _navKeycode(key);
    // Down then up, like the right-click BACK path.
    await session.control.injectKey(
      action: ScrcpyKeyAction.down,
      keycode: keycode,
    );
    await session.control.injectKey(
      action: ScrcpyKeyAction.up,
      keycode: keycode,
    );
  }

  /// Android `KEYCODE_*` for each navigation key.
  static int _navKeycode(AndroidNavKey key) => switch (key) {
    AndroidNavKey.menu => 82, // KEYCODE_MENU
    AndroidNavKey.home => 3, // KEYCODE_HOME
    AndroidNavKey.back => _androidBack, // KEYCODE_BACK (4)
    AndroidNavKey.recents => 187, // KEYCODE_APP_SWITCH
    AndroidNavKey.search => 84, // KEYCODE_SEARCH
  };

  /// Whether [text] is real printable text rather than a control character.
  ///
  /// Backspace, Enter, Tab and Escape all arrive with a non-empty control-code
  /// `character`; only code points at or above U+0020 (and not DEL) are text.
  static bool _isPrintable(String text) {
    for (final int rune in text.runes) {
      if (rune < 0x20 || rune == 0x7f) return false;
    }
    return true;
  }

  /// The Android meta-state bitmask for the modifiers held on [sample].
  static int _metaState(WindowKeySample sample) {
    var meta = 0;
    if (sample.shift) meta |= 0x01; // META_SHIFT_ON
    if (sample.alt) meta |= 0x02; // META_ALT_ON
    if (sample.ctrl) meta |= 0x1000; // META_CTRL_ON
    if (sample.meta) meta |= 0x10000; // META_META_ON
    return meta;
  }

  @override
  Future<WindowBackendSession> resizeSurface(
    String sessionId,
    WindowPixelSize pixelSize,
  ) async {
    final session = _sessions[sessionId];
    if (session == null) throw _closedFailure();
    final active = session.resizeCompletion;
    if (active != null) return active.future;
    final completion = Completer<WindowBackendSession>();
    session.resizeCompletion = completion;
    try {
      await session.control.resizeDisplay(pixelSize.width, pixelSize.height);
    } on Object {
      if (identical(session.resizeCompletion, completion)) {
        session.resizeCompletion = null;
      }
      rethrow;
    }
    return completion.future.timeout(
      const Duration(seconds: 2),
      onTimeout: () {
        if (identical(session.resizeCompletion, completion)) {
          session.resizeCompletion = null;
        }
        return session.backendSession;
      },
    );
  }

  @override
  Future<void> dispose() async {
    for (final id in [..._sessions.keys]) {
      await close(id);
    }
    await _exits.close();
    await _telemetry.close();
    await _surfaceUpdates.close();
    if (_retirements.isNotEmpty) await Future.wait([..._retirements]);
  }

  String _newScid() =>
      (_random.nextInt(0x7ffffffe) + 1).toRadixString(16).padLeft(8, '0');

  /// The display size to request for a new window, matched to the phone's
  /// natural orientation so the launcher and portrait apps start upright rather
  /// than rotated 90° inside a landscape display. Cached per device; falls back
  /// to [initialPixelSize] when adb is absent or the query fails. The app's own
  /// later rotations arrive as fresh session headers and are followed
  /// automatically, so only the starting orientation is decided here.
  Future<WindowPixelSize> _initialSizeFor(DeviceSummary device) async {
    final WindowPixelSize? cached = _naturalSizeCache[device.id];
    if (cached != null) return cached;
    WindowPixelSize size = initialPixelSize;
    final AdbClient? client = adb;
    if (client != null) {
      try {
        final String output = await client.shell(device.id, const [
          'wm',
          'size',
        ]);
        size = DisplayOrientation.fromWmSize(
          output,
          portrait: _portraitPixelSize,
          landscape: _landscapePixelSize,
          fallback: initialPixelSize,
        );
      } on Object {
        // Keep the fallback. Orientation is a nicety; a launch is not.
      }
    }
    _naturalSizeCache[device.id] = size;
    return size;
  }

  final Map<String, WindowPixelSize> _naturalSizeCache =
      <String, WindowPixelSize>{};

  static const WindowPixelSize _portraitPixelSize = WindowPixelSize(
    width: 720,
    height: 1280,
  );
  static const WindowPixelSize _landscapePixelSize = WindowPixelSize(
    width: 1280,
    height: 896,
  );

  void _validate(DeviceSummary device, AndroidApplication application) {
    if (device.id.isEmpty || device.id.contains(RegExp(r'[\x00-\x20]'))) {
      throw _failure('The Android device identifier is invalid.');
    }
    if (!_packageName.hasMatch(application.packageName)) {
      throw _failure('The Android application identifier is invalid.');
    }
  }

  /// AKEYCODE_BACK — the Android Back key, sent for a right-click.
  static const int _androidBack = 4;

  static int? _androidKeyCode(int physicalKeyId) {
    final usage = physicalKeyId & 0xffff;
    if (usage >= 0x04 && usage <= 0x1d) return 29 + usage - 0x04;
    if (usage >= 0x1e && usage <= 0x26) return 8 + usage - 0x1e;
    if (usage == 0x27) return 7;
    return const {
      0x28: 66,
      0x29: 111,
      0x2a: 67,
      0x2b: 61,
      0x2c: 62,
      0x4c: 112,
      0x4f: 22,
      0x50: 21,
      0x51: 20,
      0x52: 19,
    }[usage];
  }

  static final _packageName = RegExp(
    r'^[A-Za-z][A-Za-z0-9_]*(?:\.[A-Za-z][A-Za-z0-9_]*)+$',
  );

  static BackendFailure _failure(
    String message, [
    Object? cause,
    List<String> decoderOutput = const <String>[],
  ]) {
    final String details = <String>[
      if (cause != null) cause.toString(),
      if (decoderOutput.isNotEmpty) 'decoder: ${decoderOutput.join(' | ')}',
    ].join(' | ');
    return BackendFailure(
      OpenDexError(
        code: OpenDexErrorCode.capabilityUnavailable,
        message: message,
        retryable: true,
        capability: 'application-streaming',
        technicalDetails: details.isEmpty ? null : details,
      ),
    );
  }

  static BackendFailure _closedFailure() =>
      _failure('The Android application stream is closed.');

  static bool _sameSize(WindowPixelSize a, WindowPixelSize b) =>
      a.width == b.width && a.height == b.height;

  static Future<void> _bestEffort(Future<void> Function() operation) async {
    try {
      await operation();
    } on Object {
      // Cleanup must continue through already-closed sockets and processes.
    }
  }
}

extension on ScrcpySessionMeta {
  WindowPixelSize get pixelSize =>
      WindowPixelSize(width: width, height: height);
}

class _DecoderSurface {
  _DecoderSurface({
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

class _DirectSession {
  _DirectSession({
    required this.id,
    required this.application,
    required this.displayId,
    required this.server,
    required this.videoSocket,
    required this.controlSocket,
    required this.video,
    required this.events,
    required this.control,
    required this.surface,
    required this.latestConfig,
  });

  final String id;
  final AndroidApplication application;
  final int displayId;
  final ScrcpyServerSession server;
  final Socket videoSocket;
  final Socket controlSocket;
  final ScrcpyVideoStream video;
  final StreamIterator<ScrcpyVideoEvent> events;
  final ScrcpyControlChannel control;
  _DecoderSurface surface;
  ScrcpyVideoPacket latestConfig;
  ScrcpySessionMeta? pendingMeta;
  _DecoderSurface? replacement;
  bool replacementActivating = false;
  Completer<WindowBackendSession>? resizeCompletion;
  Timer? telemetryTimer;
  bool closed = false;

  /// Pointer ids whose gesture began with the secondary (right) button, so the
  /// rest of that gesture is swallowed after Back has been sent for it.
  final Set<int> secondaryPointers = <int>{};

  WindowBackendSession get backendSession => WindowBackendSession(
    id: id,
    displayId: displayId,
    surface: surface.windowSurface,
  );
}
