import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'scrcpy_control_messages.dart';

class ScrcpyControlChannelException implements Exception {
  const ScrcpyControlChannelException(this.message);

  final String message;

  @override
  String toString() => 'ScrcpyControlChannelException: $message';
}

class ScrcpyControlChannel {
  ScrcpyControlChannel(this._socket, {this._onClipboard}) {
    unawaited(_done.future.catchError((_) {}));
    _socket.setOption(SocketOption.tcpNoDelay, true);
    _readSubscription = _socket.listen(
      _read,
      onError: _readError,
      onDone: _readDone,
      cancelOnError: false,
    );
  }

  final Socket _socket;
  final void Function(String text)? _onClipboard;
  final Queue<_PendingControlWrite> _pending = Queue<_PendingControlWrite>();
  final Completer<void> _done = Completer<void>();
  late final StreamSubscription<List<int>> _readSubscription;
  Uint8List _readBuffer = Uint8List(4096);
  int _readOffset = 0;
  int _writeOffset = 0;
  Future<void> _drained = Future<void>.value();
  bool _draining = false;
  bool _closed = false;
  final Stopwatch _moveClock = Stopwatch()..start();
  Duration _lastMoveWrite = -_minimumMoveInterval;

  Future<void> get done => _done.future;

  Future<void> injectKey({
    required ScrcpyKeyAction action,
    required int keycode,
    int repeat = 0,
    int metaState = 0,
  }) => _submit(
    ScrcpyControlMessages.injectKey(
      action: action,
      keycode: keycode,
      repeat: repeat,
      metaState: metaState,
    ),
  );

  Future<void> injectText(String text) =>
      _submit(ScrcpyControlMessages.injectText(text));

  Future<void> injectTouch({
    required ScrcpyTouchAction action,
    required int x,
    required int y,
    required int screenWidth,
    required int screenHeight,
  }) => _submit(
    ScrcpyControlMessages.injectTouch(
      action: action,
      x: x,
      y: y,
      screenWidth: screenWidth,
      screenHeight: screenHeight,
    ),
    coalesceMove: action == ScrcpyTouchAction.move,
  );

  Future<void> injectScroll({
    required int x,
    required int y,
    required int screenWidth,
    required int screenHeight,
    required double horizontal,
    required double vertical,
  }) => _submit(
    ScrcpyControlMessages.injectScroll(
      x: x,
      y: y,
      screenWidth: screenWidth,
      screenHeight: screenHeight,
      horizontal: horizontal,
      vertical: vertical,
    ),
  );

  Future<void> getClipboard() => _submit(ScrcpyControlMessages.getClipboard());

  Future<void> setClipboard({
    required int sequence,
    required String text,
    bool paste = false,
  }) => _submit(
    ScrcpyControlMessages.setClipboard(
      sequence: sequence,
      text: text,
      paste: paste,
    ),
  );

  Future<void> startApp(String name) =>
      _submit(ScrcpyControlMessages.startApp(name));

  Future<void> resetVideo() => _submit(ScrcpyControlMessages.resetVideo());

  Future<void> resizeDisplay(int width, int height) =>
      _submit(ScrcpyControlMessages.resizeDisplay(width, height));

  Future<void> _submit(Uint8List bytes, {bool coalesceMove = false}) {
    if (_closed) {
      return Future<void>.error(
        const ScrcpyControlChannelException('The control channel is closed.'),
      );
    }
    final completion = Completer<void>();
    if (coalesceMove && _pending.isNotEmpty && _pending.last.coalesceMove) {
      _pending.last
        ..bytes = bytes
        ..completions.add(completion);
    } else {
      _pending.add(
        _PendingControlWrite(
          bytes: bytes,
          coalesceMove: coalesceMove,
          completions: [completion],
        ),
      );
    }
    if (!_draining) {
      _draining = true;
      _drained = _drain();
    }
    return completion.future;
  }

  Future<void> _drain() async {
    while (_pending.isNotEmpty) {
      final write = _pending.removeFirst();
      try {
        if (write.coalesceMove) {
          final remaining =
              _minimumMoveInterval - (_moveClock.elapsed - _lastMoveWrite);
          if (remaining > Duration.zero) await Future<void>.delayed(remaining);
          _lastMoveWrite = _moveClock.elapsed;
        }
        _socket.add(write.bytes);
        await _socket.flush();
        for (final completion in write.completions) {
          completion.complete();
        }
      } on Object catch (error, stackTrace) {
        for (final completion in write.completions) {
          completion.completeError(error, stackTrace);
        }
      }
    }
    _draining = false;
  }

  void _read(List<int> chunk) {
    if (_closed || chunk.isEmpty) return;
    _appendRead(chunk);
    _parseRead();
  }

  void _appendRead(List<int> chunk) {
    final unread = _writeOffset - _readOffset;
    if (_readBuffer.length - _writeOffset < chunk.length && _readOffset > 0) {
      _readBuffer.setRange(0, unread, _readBuffer, _readOffset);
      _readOffset = 0;
      _writeOffset = unread;
    }
    if (_readBuffer.length - _writeOffset < chunk.length) {
      var capacity = _readBuffer.length;
      final required = _writeOffset + chunk.length;
      while (capacity < required) {
        capacity *= 2;
      }
      final replacement = Uint8List(capacity)
        ..setRange(0, _writeOffset, _readBuffer);
      _readBuffer = replacement;
    }
    _readBuffer.setRange(_writeOffset, _writeOffset + chunk.length, chunk);
    _writeOffset += chunk.length;
  }

  void _parseRead() {
    while (!_closed && _writeOffset > _readOffset) {
      final type = _readBuffer[_readOffset];
      final available = _writeOffset - _readOffset;
      if (type == 0) {
        if (available < 5) return;
        final length = _readUint32(_readOffset + 1);
        if (length > _maximumClipboardBytes) {
          _failRead('The device clipboard message was too large.');
          return;
        }
        if (available < 5 + length) return;
        final text = utf8.decode(
          _readBuffer.sublist(_readOffset + 5, _readOffset + 5 + length),
          allowMalformed: true,
        );
        _readOffset += 5 + length;
        _onClipboard?.call(text);
      } else if (type == 1) {
        if (available < 9) return;
        _readOffset += 9;
      } else if (type == 2) {
        if (available < 5) return;
        final length = _readUint16(_readOffset + 3);
        if (available < 5 + length) return;
        _readOffset += 5 + length;
      } else {
        _failRead('The device sent an unknown control message type $type.');
        return;
      }
      if (_readOffset == _writeOffset) {
        _readOffset = 0;
        _writeOffset = 0;
      }
    }
  }

  int _readUint16(int offset) =>
      (_readBuffer[offset] << 8) | _readBuffer[offset + 1];

  int _readUint32(int offset) =>
      (_readBuffer[offset] << 24) |
      (_readBuffer[offset + 1] << 16) |
      (_readBuffer[offset + 2] << 8) |
      _readBuffer[offset + 3];

  void _readError(Object error, StackTrace stackTrace) {
    if (!_done.isCompleted) _done.completeError(error, stackTrace);
  }

  void _readDone() {
    if (!_done.isCompleted) _done.complete();
  }

  void _failRead(String message) {
    if (!_done.isCompleted) {
      _done.completeError(ScrcpyControlChannelException(message));
    }
    unawaited(close());
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await _drained;
    await _readSubscription.cancel();
    await _socket.close();
    if (!_done.isCompleted) _done.complete();
  }

  static const _minimumMoveInterval = Duration(microseconds: 8333);
  static const _maximumClipboardBytes = 1024 * 1024;
}

class _PendingControlWrite {
  _PendingControlWrite({
    required this.bytes,
    required this.coalesceMove,
    required this.completions,
  });

  Uint8List bytes;
  final bool coalesceMove;
  final List<Completer<void>> completions;
}
