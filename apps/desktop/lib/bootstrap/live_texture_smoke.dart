import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:open_dex_api/open_dex_api.dart';
import 'package:open_dex_texture/open_dex_texture.dart';

import '../ui/shell/app_shell.dart';
import '../ui/theme/dex_theme.dart';
import 'facade_factory.dart';

/// Short-lived, non-interactive acceptance harness for the real Linux texture.
///
/// Run only with an authorized test device. It opens two fixed Android system
/// applications, verifies native frame delivery and input routing, then tears
/// down all owned processes and tunnels.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final facade = createFacade();
  runApp(_LiveTextureSmoke(facade: facade));
}

class _LiveTextureSmoke extends StatefulWidget {
  const _LiveTextureSmoke({required this.facade});

  final OpenDexFacade facade;

  @override
  State<_LiveTextureSmoke> createState() => _LiveTextureSmokeState();
}

class _LiveTextureSmokeState extends State<_LiveTextureSmoke> {
  StreamSubscription<OpenDexSnapshot>? _states;
  OpenDexSnapshot _snapshot = const OpenDexSnapshot();
  final Map<String, double> _peakFps = {};
  String? _failure;

  @override
  void initState() {
    super.initState();
    _snapshot = widget.facade.snapshot;
    _states = widget.facade.states.listen((snapshot) {
      for (final window in snapshot.windows) {
        final fps = window.presentedFramesPerSecond;
        if (fps != null && fps > (_peakFps[window.id] ?? 0)) {
          _peakFps[window.id] = fps;
        }
      }
      if (mounted) setState(() => _snapshot = snapshot);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => unawaited(_run()));
  }

  Future<void> _run() async {
    try {
      final discovered = await widget.facade.discoverDevices();
      if (discovered case CommandFailure<List<DeviceSummary>>(:final error)) {
        throw StateError(
          'device discovery failed: ${error.message} '
          '${error.technicalDetails ?? ''}',
        );
      }
      final connected = await widget.facade.connectSelectedDevice();
      if (connected case CommandFailure<void>(:final error)) {
        throw StateError(
          'device boot failed: ${error.message} '
          '${error.technicalDetails ?? ''}',
        );
      }
      for (final packageName in const [
        'com.android.settings',
        'com.google.android.calculator',
      ]) {
        final launched = await widget.facade.launchApplication(packageName);
        if (!launched.isSuccess) {
          throw StateError('fixed smoke application unavailable');
        }
      }
      await Future<void>.delayed(const Duration(seconds: 8));
      final surfaces = widget.facade.snapshot.windows
          .map((window) => window.surface)
          .whereType<WindowSurface>()
          .toList();
      final frameCounts = await Future.wait(
        surfaces.map(
          (surface) => const OpenDexTexture().frameCount(surface.textureId),
        ),
      );
      if (surfaces.length != 2 || frameCounts.any((count) => count < 1)) {
        throw StateError(
          'one or more native textures received no video frames',
        );
      }
      stdout.writeln(
        'embedded_windows=${surfaces.length} textures_with_frames='
        '${frameCounts.where((count) => count > 0).length}',
      );
      stdout.writeln(
        'peak_fps=${_peakFps.values.map((fps) => fps.toStringAsFixed(1)).join(',')}',
      );
      final orientationWindow = widget.facade.snapshot.windows.first;
      final portrait = await widget.facade.moveWindow(
        orientationWindow.id,
        const WindowGeometry(x: 40, y: 40, width: 400, height: 700),
      );
      final portraitSurface = widget.facade.snapshot.windows.first.surface;
      final portraitFrames = portraitSurface == null
          ? 0
          : await const OpenDexTexture().frameCount(portraitSurface.textureId);
      final portraitError = switch (portrait) {
        CommandFailure<void>(:final error) =>
          '${error.message} ${error.technicalDetails ?? ''}',
        _ => 'none',
      };
      stdout.writeln(
        'portrait_result=${portrait.isSuccess} '
        'size=${portraitSurface?.pixelSize.width}x'
        '${portraitSurface?.pixelSize.height} '
        'texture=${portraitSurface?.textureId} '
        'previous=${orientationWindow.surface?.textureId} '
        'frames=$portraitFrames error=$portraitError',
      );
      if (!portrait.isSuccess ||
          portraitSurface?.pixelSize.width != 768 ||
          portraitSurface?.pixelSize.height != 1280 ||
          portraitSurface?.textureId == orientationWindow.surface?.textureId ||
          portraitFrames < 1) {
        throw StateError('portrait surface replacement failed');
      }
      final landscape = await widget.facade.moveWindow(
        orientationWindow.id,
        const WindowGeometry(x: 40, y: 40, width: 800, height: 500),
      );
      final landscapeSurface = widget.facade.snapshot.windows.first.surface;
      final landscapeFrames = landscapeSurface == null
          ? 0
          : await const OpenDexTexture().frameCount(landscapeSurface.textureId);
      final landscapeError = switch (landscape) {
        CommandFailure<void>(:final error) =>
          '${error.message} ${error.technicalDetails ?? ''}',
        _ => 'none',
      };
      stdout.writeln(
        'landscape_result=${landscape.isSuccess} '
        'size=${landscapeSurface?.pixelSize.width}x'
        '${landscapeSurface?.pixelSize.height} '
        'texture=${landscapeSurface?.textureId} '
        'previous=${portraitSurface?.textureId} '
        'frames=$landscapeFrames error=$landscapeError',
      );
      if (!landscape.isSuccess ||
          landscapeSurface?.pixelSize.width != 1280 ||
          landscapeSurface?.pixelSize.height != 752 ||
          landscapeSurface?.textureId == portraitSurface?.textureId ||
          landscapeFrames < 1) {
        throw StateError('landscape surface replacement failed');
      }
      stdout.writeln('portrait_surface=ok landscape_surface=ok');

      final windows = widget.facade.snapshot.windows;
      final pointer = await widget.facade.sendPointer(
        windows.first.id,
        const WindowPointerSample(
          phase: WindowPointerPhase.move,
          x: 640,
          y: 360,
          pointerId: 0,
        ),
      );
      final keyDown = await widget.facade.sendKey(
        windows.last.id,
        const WindowKeySample(
          phase: WindowKeyPhase.down,
          physicalKeyId: 0x00070029,
          logicalKeyId: 0x10000001b,
        ),
      );
      final keyUp = await widget.facade.sendKey(
        windows.last.id,
        const WindowKeySample(
          phase: WindowKeyPhase.up,
          physicalKeyId: 0x00070029,
          logicalKeyId: 0x10000001b,
        ),
      );
      if (!pointer.isSuccess || !keyDown.isSuccess || !keyUp.isSuccess) {
        throw StateError('embedded input routing failed');
      }
      stdout.writeln('pointer_input=ok keyboard_input=ok');

      final reconnected = await widget.facade.reconnect();
      if (!reconnected.isSuccess ||
          widget.facade.snapshot.windows.isNotEmpty ||
          widget.facade.snapshot.recovery.phase != RecoveryPhase.recovered) {
        throw StateError('embedded reconnect cleanup failed');
      }
      final relaunched = await widget.facade.launchApplication(
        'com.android.settings',
      );
      if (!relaunched.isSuccess) {
        throw StateError('post-reconnect application launch failed');
      }
      final restoredWindow = widget.facade.snapshot.windows.single;
      final restoredSurface = restoredWindow.surface;
      if (restoredSurface == null ||
          await const OpenDexTexture().frameCount(restoredSurface.textureId) <
              1) {
        throw StateError('post-reconnect texture produced no frame');
      }
      final closed = await widget.facade.closeWindow(restoredWindow.id);
      if (!closed.isSuccess || widget.facade.snapshot.windows.isNotEmpty) {
        throw StateError('embedded window close failed');
      }
      stdout.writeln('reconnect=ok relaunch=ok close=ok');
      await widget.facade.dispose();
      stdout.writeln('facade_cleanup=ok');
      exit(0);
    } on Object catch (error) {
      if (mounted) setState(() => _failure = error.toString());
      await widget.facade.dispose();
      stderr.writeln('embedded texture smoke failed: $error');
      exitCode = 1;
      await Future<void>.delayed(const Duration(seconds: 2));
      exit(1);
    }
  }

  @override
  void dispose() {
    unawaited(_states?.cancel());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: DexTheme.light(),
      darkTheme: DexTheme.dark(),
      home: Scaffold(
        body: _failure == null
            ? _snapshot.boot.isReady
                  ? AppShell(snapshot: _snapshot, facade: widget.facade)
                  : const Center(child: CircularProgressIndicator())
            : Center(child: Text(_failure!)),
      ),
    );
  }
}
