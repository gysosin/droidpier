import 'dart:async';

import 'package:open_dex_api/open_dex_api.dart';
import 'package:open_dex_core/open_dex_core.dart';

/// Runs the preferred video pipeline, and quietly uses the older one when the
/// preferred one will not start on this phone.
///
/// Measured on two real devices: the direct pipeline streams happily on a Redmi
/// Note 7 Pro (Android 13) and dies on a Galaxy F41 (Android 12) with
/// "the scrcpy video stream ended before session metadata", while the legacy
/// path streams that same phone without complaint. scrcpy's own client creates
/// a virtual display on the Galaxy without trouble, so this is not the device
/// refusing — it is the direct pipeline not coping with it, and that is worth
/// understanding separately.
///
/// Until it is, an app that will not open is a worse outcome than an app opened
/// by the older path. This is a bridge, not a resolution, and it says so.
class FallbackWindowGateway implements WindowGateway, UrlWindowGateway {
  FallbackWindowGateway({required this.preferred, required this.fallback});

  final WindowGateway preferred;
  final WindowGateway fallback;

  /// Devices whose preferred pipeline has already failed once.
  ///
  /// Retrying a path that has failed on this phone costs the person the whole
  /// start-up timeout on every launch, which reads as the product being slow
  /// rather than as it recovering.
  final Set<String> _demoted = <String>{};

  /// Which gateway owns a live session, so close and input go to the right one.
  final Map<String, WindowGateway> _owners = <String, WindowGateway>{};

  @override
  Stream<WindowBackendExit> get exits =>
      _merge<WindowBackendExit>(preferred.exits, fallback.exits);

  @override
  Stream<WindowBackendTelemetry> get telemetry =>
      _merge<WindowBackendTelemetry>(preferred.telemetry, fallback.telemetry);

  /// Both gateways' events, on one stream.
  ///
  /// Hand-rolled rather than pulled from `package:async`: this needs one
  /// function and the plugin has no other reason to take the dependency. The
  /// controller closes only once both sources have, so a consumer does not see
  /// the stream end while the other pipeline is still running.
  static Stream<T> _merge<T>(Stream<T> a, Stream<T> b) {
    late final StreamController<T> controller;
    var open = 2;
    void closeOne() {
      open -= 1;
      if (open == 0) unawaited(controller.close());
    }

    final List<StreamSubscription<T>> subscriptions = <StreamSubscription<T>>[];
    controller = StreamController<T>.broadcast(
      onListen: () {
        for (final Stream<T> source in <Stream<T>>[a, b]) {
          subscriptions.add(
            source.listen(
              controller.add,
              onError: controller.addError,
              onDone: closeOne,
            ),
          );
        }
      },
      onCancel: () async {
        for (final StreamSubscription<T> s in subscriptions) {
          await s.cancel();
        }
        subscriptions.clear();
      },
    );
    return controller.stream;
  }

  @override
  Future<WindowBackendSession> launch(
    DeviceSummary device,
    AndroidApplication application, {
    String? sessionId,
  }) async {
    if (!_demoted.contains(device.id)) {
      try {
        final WindowBackendSession session = await preferred.launch(
          device,
          application,
          sessionId: sessionId,
        );
        _owners[session.id] = preferred;
        return session;
      } on Object catch (error, stack) {
        _demoted.add(device.id);
        return _useFallback(
          device,
          application,
          sessionId: sessionId,
          // Kept so that if the older path fails too, the person is told why
          // the *intended* one did. That is the failure worth acting on.
          originalError: error,
          originalStack: stack,
        );
      }
    }
    return _useFallback(device, application, sessionId: sessionId);
  }

  /// The path that can open web addresses for this phone: the preferred one
  /// unless it has been demoted, else the older one, else none.
  ///
  /// An address failing to open never demotes: it says the browser refused,
  /// not that the video pipeline cannot start on this phone.
  UrlWindowGateway _urlPath(DeviceSummary device) {
    final WindowGateway first = _demoted.contains(device.id)
        ? fallback
        : preferred;
    final WindowGateway second = identical(first, preferred)
        ? fallback
        : preferred;
    for (final WindowGateway candidate in <WindowGateway>[first, second]) {
      if (candidate is UrlWindowGateway) return candidate as UrlWindowGateway;
    }
    throw const BackendFailure(
      OpenDexError(
        code: OpenDexErrorCode.capabilityUnavailable,
        message: 'This build cannot open web addresses on the phone.',
        capability: 'phone-browser',
      ),
    );
  }

  @override
  Future<String?> resolveBrowser(DeviceSummary device, String url) async =>
      _urlPath(device).resolveBrowser(device, url);

  @override
  Future<WindowBackendSession> launchUrl(
    DeviceSummary device,
    AndroidApplication browser,
    String url, {
    String? sessionId,
  }) async {
    final UrlWindowGateway path = _urlPath(device);
    final WindowBackendSession session = await path.launchUrl(
      device,
      browser,
      url,
      sessionId: sessionId,
    );
    _owners[session.id] = path as WindowGateway;
    return session;
  }

  Future<WindowBackendSession> _useFallback(
    DeviceSummary device,
    AndroidApplication application, {
    String? sessionId,
    Object? originalError,
    StackTrace? originalStack,
  }) async {
    try {
      final WindowBackendSession session = await fallback.launch(
        device,
        application,
        sessionId: sessionId,
      );
      _owners[session.id] = fallback;
      return session;
    } on Object {
      // Both refused. Report the preferred pipeline's reason: it is the one the
      // product means to use, so it is the one whose failure is diagnostic.
      if (originalError != null) {
        Error.throwWithStackTrace(
          originalError,
          originalStack ?? StackTrace.current,
        );
      }
      rethrow;
    }
  }

  WindowGateway _ownerOf(String sessionId) => _owners[sessionId] ?? preferred;

  @override
  Future<void> close(String sessionId) async {
    await _ownerOf(sessionId).close(sessionId);
    _owners.remove(sessionId);
  }

  @override
  Future<void> sendPointer(String sessionId, WindowPointerSample sample) =>
      _ownerOf(sessionId).sendPointer(sessionId, sample);

  @override
  Future<void> sendKey(String sessionId, WindowKeySample sample) =>
      _ownerOf(sessionId).sendKey(sessionId, sample);

  @override
  Future<void> dispose() async {
    await preferred.dispose();
    await fallback.dispose();
  }
}
