import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:open_dex_api/open_dex_api.dart';
import 'package:open_dex_core/open_dex_core.dart';

import '../process_executor.dart';
import 'decoder_surface.dart';
import 'h264_decoder_process.dart';
import 'scrcpy_frames.dart';
import 'scrcpy_server_launcher.dart';
import 'scrcpy_video_stream.dart';

/// Streams the phone's own display to a desktop texture, view only.
///
/// The window gateway's pipeline with the parts a mirror does not need taken
/// out: scrcpy-server is started against display 0 rather than a new virtual
/// display, and with no control socket, so the phone keeps driving what is
/// shown and nothing here can inject into it. One mirror runs at a time.
///
/// Without a control channel a decoder that dies cannot ask the phone for a
/// fresh key frame, so there is no restart: the session ends with exit 22 and
/// the desk offers a retry, which starts a fresh server and gets one anyway.
class DirectScrcpyDisplayMirrorGateway implements DisplayMirrorGateway {
  DirectScrcpyDisplayMirrorGateway({
    required this.mirrorStarter,
    required this.decoderStarter,
    required this.serverJarPath,
    required this.ffmpegExecutable,
    required this.textureHost,
    this.processExecutor = const SystemProcessExecutor(),
    this.startTimeout = const Duration(seconds: 15),
    this.firstFrameTimeout = const Duration(seconds: 10),
    this.surfaceRetireDelay = const Duration(milliseconds: 250),
    this.maxSize = 540,
    this.maxFps = 30,
  }) {
    if (startTimeout <= Duration.zero || firstFrameTimeout <= Duration.zero) {
      throw ArgumentError('Mirror timeouts must be greater than zero.');
    }
    if (surfaceRetireDelay.isNegative) {
      throw ArgumentError('The surface retire delay cannot be negative.');
    }
  }

  final ScrcpyMirrorStarter mirrorStarter;
  final H264DecoderStarter decoderStarter;
  final String serverJarPath;
  final String ffmpegExecutable;
  final WindowTextureHost textureHost;
  final ProcessExecutor processExecutor;
  final Duration startTimeout;
  final Duration firstFrameTimeout;
  final Duration surfaceRetireDelay;

  /// The longer side of the mirrored frame in pixels; scrcpy scales the
  /// display down to it. The desk draws the mirror small, so the default is
  /// half the phone's width, which keeps the phone's encoder free for the
  /// app windows streaming beside it.
  final int maxSize;
  final int maxFps;

  final StreamController<MirrorBackendExit> _exits =
      StreamController<MirrorBackendExit>.broadcast(sync: true);
  final StreamController<MirrorBackendSession> _surfaceUpdates =
      StreamController<MirrorBackendSession>.broadcast(sync: true);
  late final DecoderSurfaceOpener _surfaces = DecoderSurfaceOpener(
    textureHost: textureHost,
    decoderStarter: decoderStarter,
    ffmpegExecutable: ffmpegExecutable,
    processExecutor: processExecutor,
  );
  final Set<Future<void>> _retirements = {};
  final Random _random = Random.secure();
  _MirrorSession? _session;
  bool _starting = false;
  var _sequence = 0;

  @override
  Stream<MirrorBackendExit> get exits => _exits.stream;

  @override
  Stream<MirrorBackendSession> get surfaceUpdates => _surfaceUpdates.stream;

  @override
  Future<MirrorBackendSession> start(DeviceSummary device) async {
    if (_session != null || _starting) {
      throw _failure('The phone screen is already being mirrored.');
    }
    if (device.status != DeviceStatus.authorized) {
      throw _failure('The selected device is not authorized for streaming.');
    }
    _starting = true;
    final id =
        'mirror-${DateTime.now().toUtc().microsecondsSinceEpoch.toRadixString(36)}-${++_sequence}';
    ServerSocket? listener;
    StreamIterator<Socket>? accepts;
    ScrcpyServerSession? server;
    Socket? videoSocket;
    ScrcpyVideoStream? video;
    StreamIterator<ScrcpyVideoEvent>? events;
    DecoderSurface? surface;
    try {
      listener = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      accepts = StreamIterator<Socket>(listener);
      server = await mirrorStarter.startMirror(
        device: device,
        serverJarPath: serverJarPath,
        hostPort: listener.port,
        scid: _newScid(),
        maxSize: maxSize,
        maxFps: maxFps,
      );
      if (!await accepts.moveNext().timeout(startTimeout)) {
        throw TimeoutException('The scrcpy video socket did not connect.');
      }
      videoSocket = accepts.current;
      await accepts.cancel();
      accepts = null;
      await listener.close();
      listener = null;
      video = ScrcpyVideoStream(videoSocket);
      events = StreamIterator<ScrcpyVideoEvent>(video.events);
      await video.deviceName.timeout(startTimeout);
      final codec = await video.codecId.timeout(startTimeout);
      if (codec != 0x68323634) {
        throw BackendFailure(
          OpenDexError(
            code: OpenDexErrorCode.capabilityUnavailable,
            message: 'scrcpy-server selected an unsupported video codec.',
            retryable: false,
            capability: _capability,
            technicalDetails: 'codec=0x${codec.toRadixString(16)}',
          ),
        );
      }
      final configured = await _nextConfiguredSession(events)
          .timeout(startTimeout);
      surface = await _surfaces.open(
        configured.meta.pixelSize,
        configured.config,
        resetVideo: _noReset,
        onFailure: _failure,
      );
      await _feedUntilFirstFrame(events, surface);
      final session = _MirrorSession(
        id: id,
        server: server,
        videoSocket: videoSocket,
        video: video,
        events: events,
        surface: surface,
      );
      _session = session;
      _watchServer(session);
      _watchDecoder(session, surface);
      unawaited(_consumeVideo(session));
      return session.backendSession;
    } on BackendFailure {
      await _cleanupPartial(
        listener: listener,
        accepts: accepts,
        server: server,
        videoSocket: videoSocket,
        video: video,
        events: events,
        surface: surface,
      );
      rethrow;
    } on Object catch (error) {
      await _cleanupPartial(
        listener: listener,
        accepts: accepts,
        server: server,
        videoSocket: videoSocket,
        video: video,
        events: events,
        surface: surface,
      );
      throw _failure(
        'The phone screen stream could not start.',
        error,
        surface?.decoder.outputTail ?? const <String>[],
      );
    } finally {
      _starting = false;
    }
  }

  /// Feeds the decoder until the texture reports a frame, as the window
  /// gateway does: a software H.264 decoder emits frame N only once frame
  /// N+1 arrives, so stopping at the first key frame would starve the very
  /// frame being waited for.
  Future<void> _feedUntilFirstFrame(
    StreamIterator<ScrcpyVideoEvent> events,
    DecoderSurface surface,
  ) async {
    final Future<void> firstFrame = textureHost.waitForFirstFrame(
      surface.textureId,
      timeout: firstFrameTimeout,
    );
    var firstFrameSettled = false;
    unawaited(
      firstFrame.then<void>(
        (_) => firstFrameSettled = true,
        onError: (Object _, StackTrace _) => firstFrameSettled = true,
      ),
    );
    var sawKeyFrame = false;
    while (!firstFrameSettled) {
      final bool hasEvent;
      try {
        hasEvent = await events.moveNext().timeout(startTimeout);
      } on TimeoutException {
        break;
      }
      if (!hasEvent) break;
      final event = events.current;
      if (event is ScrcpyVideoPacket) {
        surface.decoder.feed(event);
        sawKeyFrame = sawKeyFrame || event.isKeyFrame;
      }
    }
    await firstFrame;
    if (!sawKeyFrame) {
      throw const ScrcpyVideoStreamException(
        'The scrcpy video stream ended before its first key frame.',
      );
    }
  }

  Future<({ScrcpySessionMeta meta, ScrcpyVideoPacket config})>
  _nextConfiguredSession(StreamIterator<ScrcpyVideoEvent> events) async {
    ScrcpySessionMeta? meta;
    while (await events.moveNext()) {
      final event = events.current;
      if (event is ScrcpySessionMeta) {
        meta = event;
      } else if (event is ScrcpyVideoPacket && event.isConfig) {
        if (meta == null) break;
        return (meta: meta, config: event);
      }
    }
    throw const ScrcpyVideoStreamException(
      'The scrcpy video stream ended before decoder configuration.',
    );
  }

  Future<void> _consumeVideo(_MirrorSession session) async {
    try {
      while (!session.closed && await session.events.moveNext()) {
        final event = session.events.current;
        if (event is ScrcpySessionMeta) {
          session.pendingMeta = event;
          continue;
        }
        if (event is! ScrcpyVideoPacket) continue;
        if (event.isConfig) {
          final meta = session.pendingMeta;
          session.pendingMeta = null;
          if (meta != null &&
              !_sameSize(meta.pixelSize, session.surface.pixelSize)) {
            await _prepareReplacement(session, meta, event);
          } else {
            (session.replacement ?? session.surface).decoder.feed(event);
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

  /// The phone rotated: its next frames have a new shape, which needs a new
  /// texture. The old surface keeps its last frame until the new one has
  /// drawn, so the desk never shows a blank while the phone turns.
  Future<void> _prepareReplacement(
    _MirrorSession session,
    ScrcpySessionMeta meta,
    ScrcpyVideoPacket config,
  ) async {
    final stale = session.replacement;
    session.replacement = null;
    session.replacementActivating = false;
    if (stale != null) await stale.dispose(textureHost);
    final replacement = await _surfaces.open(
      meta.pixelSize,
      config,
      resetVideo: _noReset,
      onFailure: _failure,
    );
    if (session.closed) {
      await replacement.dispose(textureHost);
      return;
    }
    session.replacement = replacement;
    _watchDecoder(session, replacement);
  }

  Future<void> _activateReplacement(
    _MirrorSession session,
    DecoderSurface replacement,
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
      if (!_surfaceUpdates.isClosed) {
        _surfaceUpdates.add(session.backendSession);
      }
      final retirement = Future<void>.delayed(
        surfaceRetireDelay,
        () => old.dispose(textureHost),
      );
      _retirements.add(retirement);
      unawaited(retirement.whenComplete(() => _retirements.remove(retirement)));
    } on Object {
      if (session.closed) return;
      if (identical(session.replacement, replacement)) {
        session.replacement = null;
        session.replacementActivating = false;
      }
      await replacement.dispose(textureHost);
      // The frames now arriving have the new shape and the old surface has
      // the old one; feeding it would draw garbage. End honestly instead.
      await _unexpectedExit(session, 23);
    }
  }

  void _watchServer(_MirrorSession session) {
    unawaited(
      session.server.exitCode.then((_) {
        if (!session.closed) return _unexpectedExit(session, 21);
      }),
    );
  }

  void _watchDecoder(_MirrorSession session, DecoderSurface surface) {
    unawaited(
      surface.decoder.exitCode.then((_) async {
        if (session.closed) return;
        final owned =
            identical(session.surface, surface) ||
            identical(session.replacement, surface);
        if (!owned) return;
        await _unexpectedExit(session, 22);
      }),
    );
  }

  Future<void> _unexpectedExit(_MirrorSession session, int exitCode) async {
    if (!identical(_session, session)) return;
    _session = null;
    await _disposeSession(session);
    if (_exits.isClosed) return;
    final details = switch (exitCode) {
      21 when session.server.stderrTail.isNotEmpty =>
        session.server.stderrTail.join(' | '),
      21 => 'scrcpy-server stopped',
      22 => 'the video decoder stopped',
      23 => 'the mirror could not follow the phone rotating',
      _ => 'display mirror exit code $exitCode',
    };
    _exits.add(
      MirrorBackendExit(
        sessionId: session.id,
        exitCode: exitCode,
        details: details,
      ),
    );
  }

  @override
  Future<void> stop(String sessionId) async {
    final session = _session;
    if (session == null || session.id != sessionId) return;
    _session = null;
    await _disposeSession(session);
  }

  Future<void> _disposeSession(_MirrorSession session) async {
    if (session.closed) return;
    session.closed = true;
    await _bestEffort(session.events.cancel);
    await _bestEffort(session.video.dispose);
    await _bestEffort(session.videoSocket.close);
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
    required ScrcpyVideoStream? video,
    required StreamIterator<ScrcpyVideoEvent>? events,
    required DecoderSurface? surface,
  }) async {
    if (accepts != null) await _bestEffort(accepts.cancel);
    if (events != null) await _bestEffort(events.cancel);
    if (video != null) await _bestEffort(video.dispose);
    if (videoSocket != null) await _bestEffort(videoSocket.close);
    if (surface != null) {
      await _bestEffort(() => surface.dispose(textureHost));
    }
    if (server != null) await _bestEffort(server.stop);
    if (listener != null) await _bestEffort(listener.close);
  }

  @override
  Future<void> dispose() async {
    final session = _session;
    if (session != null) await stop(session.id);
    await _exits.close();
    await _surfaceUpdates.close();
    if (_retirements.isNotEmpty) await Future.wait([..._retirements]);
  }

  String _newScid() =>
      (_random.nextInt(0x7ffffffe) + 1).toRadixString(16).padLeft(8, '0');

  static const String _capability = 'display-mirror';

  /// No control socket, so nothing to reset; the decoder is told as much.
  static Future<void> _noReset() async {}

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
        capability: _capability,
        technicalDetails: details.isEmpty ? null : details,
      ),
    );
  }

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

class _MirrorSession {
  _MirrorSession({
    required this.id,
    required this.server,
    required this.videoSocket,
    required this.video,
    required this.events,
    required this.surface,
  });

  final String id;
  final ScrcpyServerSession server;
  final Socket videoSocket;
  final ScrcpyVideoStream video;
  final StreamIterator<ScrcpyVideoEvent> events;
  DecoderSurface surface;
  ScrcpySessionMeta? pendingMeta;
  DecoderSurface? replacement;
  bool replacementActivating = false;
  bool closed = false;

  MirrorBackendSession get backendSession =>
      MirrorBackendSession(id: id, surface: surface.windowSurface);
}

extension on ScrcpySessionMeta {
  WindowPixelSize get pixelSize =>
      WindowPixelSize(width: width, height: height);
}
