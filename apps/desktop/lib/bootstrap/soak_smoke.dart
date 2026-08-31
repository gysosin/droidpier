import 'dart:async';
import 'dart:io';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:open_dex_api/open_dex_api.dart';

import 'facade_factory.dart';

Future<void> main(List<String> arguments) async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    _SoakSmoke(
      facade: createFacade(),
      configuration: _SoakConfiguration.parse(arguments),
    ),
  );
}

class _SoakConfiguration {
  const _SoakConfiguration({required this.minutes, this.iterations});

  factory _SoakConfiguration.parse(List<String> arguments) {
    int read(String name, int fallback) {
      for (var index = 0; index < arguments.length; index += 1) {
        final argument = arguments[index];
        if (argument.startsWith('--$name=')) {
          return int.parse(argument.substring(name.length + 3));
        }
        if (argument == '--$name' && index + 1 < arguments.length) {
          return int.parse(arguments[index + 1]);
        }
      }
      return fallback;
    }

    final iterations = read('iterations', 0);
    return _SoakConfiguration(
      minutes: read('minutes', 30).clamp(1, 1440),
      iterations: iterations > 0 ? iterations : null,
    );
  }

  final int minutes;
  final int? iterations;
}

class _SoakSmoke extends StatefulWidget {
  const _SoakSmoke({required this.facade, required this.configuration});

  final OpenDexFacade facade;
  final _SoakConfiguration configuration;

  @override
  State<_SoakSmoke> createState() => _SoakSmokeState();
}

class _SoakSmokeState extends State<_SoakSmoke> {
  StreamSubscription<OpenDexSnapshot>? _states;
  OpenDexSnapshot _snapshot = const OpenDexSnapshot();
  Timer? _watchdog;
  var _frameworkErrors = 0;

  @override
  void initState() {
    super.initState();
    _snapshot = widget.facade.snapshot;
    _states = widget.facade.states.listen((snapshot) {
      _snapshot = snapshot;
      if (mounted) setState(() {});
    });
    final oldFlutterError = FlutterError.onError;
    FlutterError.onError = (details) {
      _frameworkErrors += 1;
      oldFlutterError?.call(details);
    };
    final oldPlatformError = PlatformDispatcher.instance.onError;
    PlatformDispatcher.instance.onError = (error, stackTrace) {
      _frameworkErrors += 1;
      return oldPlatformError?.call(error, stackTrace) ?? false;
    };
    _watchdog = Timer(
      Duration(minutes: widget.configuration.minutes + 5),
      () => unawaited(_abortForTimeout()),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) => unawaited(_run()));
  }

  Future<void> _run() async {
    var exitStatus = 1;
    try {
      _requireSuccess(
        await widget.facade.discoverDevices(),
        'device discovery',
      );
      _requireSuccess(
        await widget.facade.connectSelectedDevice(),
        'device connection',
      );
      for (final packageName in const [
        'com.android.settings',
        'com.google.android.calculator',
      ]) {
        if (!widget.facade.snapshot.applications.any(
          (application) => application.packageName == packageName,
        )) {
          throw StateError('Required soak application is absent: $packageName');
        }
      }

      final baseline = await _resources();
      final initialDirectories = await _windowTemporaryDirectories();
      final elapsed = Stopwatch()..start();
      var loop = 0;
      while (_keepRunning(elapsed.elapsed, loop)) {
        loop += 1;
        await _runLoop();
        await Future<void>.delayed(const Duration(milliseconds: 300));
        final current = await _resources();
        final newDirectories = (await _windowTemporaryDirectories()).difference(
          initialDirectories,
        );
        if (current.children > baseline.children ||
            current.fileDescriptors > baseline.fileDescriptors + 4 ||
            current.rssBytes > baseline.rssBytes + 50 * 1024 * 1024 ||
            newDirectories.isNotEmpty ||
            _frameworkErrors > 0) {
          throw StateError(
            'resource growth after loop $loop: '
            'children=${current.children}/${baseline.children} '
            'fds=${current.fileDescriptors}/${baseline.fileDescriptors} '
            'rss=${current.rssBytes}/${baseline.rssBytes} '
            'temp=${newDirectories.length} errors=$_frameworkErrors',
          );
        }
        stdout.writeln(
          'soak loop=$loop children=${current.children} '
          'fds=${current.fileDescriptors} rss=${current.rssBytes} '
          'temp=0 errors=0',
        );
      }

      await widget.facade.dispose();
      await Future<void>.delayed(const Duration(milliseconds: 300));
      final remainingChildren = (await _descendantPids(pid)).length;
      final remainingDirectories = (await _windowTemporaryDirectories())
          .difference(initialDirectories);
      if (remainingChildren != 0 || remainingDirectories.isNotEmpty) {
        throw StateError(
          'final cleanup leaked children=$remainingChildren '
          'temp=${remainingDirectories.length}',
        );
      }
      stdout.writeln(
        'soak passed loops=$loop minutes=${elapsed.elapsed.inMinutes} '
        'rss_growth=${(await _rssBytes()) - baseline.rssBytes}',
      );
      exitStatus = 0;
    } on Object catch (error, stackTrace) {
      stderr.writeln('soak failed: $error');
      stderr.writeln(stackTrace);
      await _bestEffortDispose();
    }
    _watchdog?.cancel();
    await _states?.cancel();
    exit(exitStatus);
  }

  bool _keepRunning(Duration elapsed, int completedLoops) {
    final iterations = widget.configuration.iterations;
    if (iterations != null) return completedLoops < iterations;
    return elapsed < Duration(minutes: widget.configuration.minutes);
  }

  Future<void> _runLoop() async {
    for (final packageName in const [
      'com.android.settings',
      'com.google.android.calculator',
    ]) {
      _successValue(
        await widget.facade.launchApplication(packageName),
        'launch $packageName',
      );
    }
    for (final geometry in const [
      WindowGeometry(x: 30, y: 30, width: 900, height: 700),
      WindowGeometry(x: 60, y: 45, width: 500, height: 800),
      WindowGeometry(x: 80, y: 60, width: 760, height: 520),
      WindowGeometry(x: 100, y: 75, width: 420, height: 760),
    ]) {
      for (final window in [...widget.facade.snapshot.windows]) {
        _requireSuccess(
          await widget.facade.moveWindow(window.id, geometry),
          'resize ${window.application.packageName}',
        );
      }
    }
    final rotating = widget.facade.snapshot.windows.first;
    _requireSuccess(
      await widget.facade.moveWindow(
        rotating.id,
        const WindowGeometry(x: 40, y: 40, width: 900, height: 600),
      ),
      'rotate landscape',
    );
    _requireSuccess(
      await widget.facade.moveWindow(
        rotating.id,
        const WindowGeometry(x: 40, y: 40, width: 430, height: 780),
      ),
      'rotate portrait',
    );

    _requireSuccess(
      await widget.facade.closeWindow(widget.facade.snapshot.windows.last.id),
      'close second application',
    );
    _requireSuccess(await widget.facade.reconnect(), 'device reconnect');
    if (widget.facade.snapshot.windows.isNotEmpty) {
      throw StateError('Reconnect retained stale windows.');
    }
    _successValue(
      await widget.facade.launchApplication('com.android.settings'),
      'post-reconnect launch',
    );
    for (final window in [...widget.facade.snapshot.windows]) {
      _requireSuccess(
        await widget.facade.closeWindow(window.id),
        'final window close',
      );
    }
  }

  T _successValue<T>(CommandResult<T> result, String operation) {
    if (result case CommandSuccess<T>(:final value)) return value;
    _requireSuccess(result, operation);
    throw StateError('$operation returned no value.');
  }

  void _requireSuccess<T>(CommandResult<T> result, String operation) {
    if (result case CommandFailure<T>(:final error)) {
      throw StateError(
        '$operation failed: ${error.message} ${error.technicalDetails ?? ''}',
      );
    }
  }

  Future<_Resources> _resources() async => _Resources(
    children: (await _descendantPids(pid)).length,
    fileDescriptors: await Directory('/proc/$pid/fd').list().length,
    rssBytes: await _rssBytes(),
  );

  Future<int> _rssBytes() async {
    final status = await File('/proc/$pid/status').readAsLines();
    final line = status.firstWhere((value) => value.startsWith('VmRSS:'));
    final kibibytes = int.parse(line.trim().split(RegExp(r'\s+'))[1]);
    return kibibytes * 1024;
  }

  Future<void> _abortForTimeout() async {
    stderr.writeln('soak failed: hard timeout exceeded');
    await _bestEffortDispose();
    exit(2);
  }

  Future<void> _bestEffortDispose() async {
    try {
      await widget.facade.dispose().timeout(const Duration(seconds: 15));
    } on Object {
      // The primary soak failure remains the useful diagnostic.
    }
  }

  @override
  void dispose() {
    _watchdog?.cancel();
    unawaited(_states?.cancel());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final surfaces = _snapshot.windows
        .map((window) => window.surface)
        .whereType<WindowSurface>()
        .toList();
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: ColoredBox(
        color: Colors.black,
        child: Column(
          children: [
            for (final surface in surfaces)
              Expanded(
                child: Texture(
                  textureId: surface.textureId,
                  filterQuality: FilterQuality.low,
                ),
              ),
            if (surfaces.isEmpty) const Expanded(child: SizedBox()),
          ],
        ),
      ),
    );
  }
}

class _Resources {
  const _Resources({
    required this.children,
    required this.fileDescriptors,
    required this.rssBytes,
  });

  final int children;
  final int fileDescriptors;
  final int rssBytes;
}

Future<Set<int>> _descendantPids(int rootPid) async {
  final children = <int, List<int>>{};
  await for (final entity in Directory('/proc').list()) {
    final processId = int.tryParse(entity.path.split('/').last);
    if (processId == null) continue;
    try {
      final stat = await File('/proc/$processId/stat').readAsString();
      final commandEnd = stat.lastIndexOf(')');
      if (commandEnd < 0) continue;
      final fields = stat.substring(commandEnd + 2).trim().split(' ');
      final parent = int.tryParse(fields[1]);
      if (parent != null) children.putIfAbsent(parent, () => []).add(processId);
    } on FileSystemException {
      // The process exited while /proc was sampled.
    }
  }
  final descendants = <int>{};
  final pending = <int>[rootPid];
  while (pending.isNotEmpty) {
    final parent = pending.removeLast();
    for (final child in children[parent] ?? const <int>[]) {
      if (descendants.add(child)) pending.add(child);
    }
  }
  return descendants;
}

Future<Set<String>> _windowTemporaryDirectories() async {
  final result = <String>{};
  await for (final entity in Directory.systemTemp.list()) {
    if (entity is Directory &&
        entity.path
            .split(Platform.pathSeparator)
            .last
            .startsWith('open-dex-window-')) {
      result.add(entity.path);
    }
  }
  return result;
}
