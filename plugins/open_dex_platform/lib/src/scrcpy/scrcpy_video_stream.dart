import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'scrcpy_frames.dart';

class ScrcpyVideoStreamException implements Exception {
  const ScrcpyVideoStreamException(this.message);

  final String message;

  @override
  String toString() => 'ScrcpyVideoStreamException: $message';
}

class ScrcpyVideoStream {
  ScrcpyVideoStream(Stream<List<int>> input) {
    unawaited(_deviceName.future.catchError((_) => ''));
    unawaited(_codecId.future.catchError((_) => -1));
    _subscription = input.listen(
      _add,
      onError: _inputError,
      onDone: _inputDone,
      cancelOnError: false,
    );
  }

  final Completer<String> _deviceName = Completer<String>();
  final Completer<int> _codecId = Completer<int>();
  // A single-subscription controller buffers the first session header and
  // CONFIG packet if the socket starts producing before the gateway listens.
  final StreamController<ScrcpyVideoEvent> _events =
      StreamController<ScrcpyVideoEvent>(sync: true);
  late final StreamSubscription<List<int>> _subscription;
  Uint8List _buffer = Uint8List(4096);
  int _readOffset = 0;
  int _writeOffset = 0;
  int _state = _stateDeviceName;
  int _packetSize = 0;
  int _packetPts = 0;
  bool _packetConfig = false;
  bool _packetKeyFrame = false;
  ScrcpySessionMeta? _latestSessionMeta;
  ScrcpyVideoPacket? _latestConfig;
  bool _failed = false;
  bool _disposed = false;

  Future<String> get deviceName => _deviceName.future;

  Future<int> get codecId => _codecId.future;

  Stream<ScrcpyVideoEvent> get events => _events.stream;

  ScrcpySessionMeta? get latestSessionMeta => _latestSessionMeta;

  ScrcpyVideoPacket? get latestConfig => _latestConfig;

  void _add(List<int> chunk) {
    if (_failed || _disposed || chunk.isEmpty) return;
    _append(chunk);
    _parse();
  }

  void _append(List<int> chunk) {
    final unread = _writeOffset - _readOffset;
    if (_buffer.length - _writeOffset < chunk.length && _readOffset > 0) {
      _buffer.setRange(0, unread, _buffer, _readOffset);
      _readOffset = 0;
      _writeOffset = unread;
    }
    if (_buffer.length - _writeOffset < chunk.length) {
      var capacity = _buffer.length;
      final required = _writeOffset + chunk.length;
      while (capacity < required) {
        capacity *= 2;
        if (capacity > _maximumBufferedBytes) {
          capacity = _maximumBufferedBytes;
          break;
        }
      }
      if (capacity < required) {
        _fail(
          const ScrcpyVideoStreamException(
            'The scrcpy video packet exceeded the buffer limit.',
          ),
        );
        return;
      }
      final replacement = Uint8List(capacity)
        ..setRange(0, _writeOffset, _buffer);
      _buffer = replacement;
    }
    _buffer.setRange(_writeOffset, _writeOffset + chunk.length, chunk);
    _writeOffset += chunk.length;
  }

  void _parse() {
    while (!_failed && !_disposed) {
      final available = _writeOffset - _readOffset;
      if (_state == _stateDeviceName) {
        if (available < 64) return;
        final bytes = _buffer.sublist(_readOffset, _readOffset + 64);
        final terminator = bytes.indexOf(0);
        _deviceName.complete(
          utf8.decode(
            terminator < 0 ? bytes : bytes.sublist(0, terminator),
            allowMalformed: true,
          ),
        );
        _readOffset += 64;
        _state = _stateCodec;
        continue;
      }
      if (_state == _stateCodec) {
        if (available < 4) return;
        final codec = _readUint32(_readOffset);
        _readOffset += 4;
        if (codec == 0 || codec == 1) {
          final reason = codec == 1
              ? 'scrcpy-server could not configure the video stream.'
              : 'scrcpy-server disabled the video stream.';
          final error = ScrcpyVideoStreamException(reason);
          _codecId.completeError(error);
          _fail(error, codecAlreadyCompleted: true);
          return;
        }
        _codecId.complete(codec);
        _state = _stateHeader;
        continue;
      }
      if (_state == _stateHeader) {
        if (available < 12) return;
        // Consume bit-63 session headers before reading packet ptsFlags. This
        // keeps _readUint64 sign-safe and matches Streamer.writeSessionMeta().
        if ((_buffer[_readOffset] & 0x80) != 0) {
          final clientResized = (_buffer[_readOffset + 3] & 1) != 0;
          final width = _readUint32(_readOffset + 4);
          final height = _readUint32(_readOffset + 8);
          _readOffset += 12;
          if (width < 1 || height < 1 || width > 65535 || height > 65535) {
            _fail(
              ScrcpyVideoStreamException(
                'scrcpy-server reported an invalid video size '
                '${width}x$height.',
              ),
            );
            return;
          }
          final session = ScrcpySessionMeta(
            width: width,
            height: height,
            clientResized: clientResized,
          );
          _latestSessionMeta = session;
          _events.add(session);
          _resetOffsetsIfEmpty();
          continue;
        }
        final ptsFlags = _readUint64(_readOffset);
        _packetSize = _readUint32(_readOffset + 8);
        _packetConfig = (ptsFlags & _configFlag) != 0;
        _packetKeyFrame = (ptsFlags & _keyFrameFlag) != 0;
        _packetPts = ptsFlags & _ptsMask;
        _readOffset += 12;
        if (_packetSize > _maximumPacketBytes) {
          _fail(
            ScrcpyVideoStreamException(
              'scrcpy-server declared an oversized video packet '
              '($_packetSize bytes).',
            ),
          );
          return;
        }
        _state = _statePacket;
        continue;
      }
      if (_state == _statePacket) {
        if (available < _packetSize) return;
        final data = Uint8List.fromList(
          _buffer.sublist(_readOffset, _readOffset + _packetSize),
        );
        _readOffset += _packetSize;
        final packet = ScrcpyVideoPacket(
          pts: _packetPts,
          isConfig: _packetConfig,
          isKeyFrame: _packetKeyFrame,
          data: data,
        );
        if (packet.isConfig) _latestConfig = packet;
        // Restore every parser invariant before invoking a synchronous
        // listener. A listener may re-enter through the input stream (for
        // example while swapping a decoder during resize).
        _state = _stateHeader;
        _resetOffsetsIfEmpty();
        _events.add(packet);
      }
    }
  }

  int _readUint32(int offset) =>
      (_buffer[offset] << 24) |
      (_buffer[offset + 1] << 16) |
      (_buffer[offset + 2] << 8) |
      _buffer[offset + 3];

  int _readUint64(int offset) =>
      (_readUint32(offset) << 32) | _readUint32(offset + 4);

  void _resetOffsetsIfEmpty() {
    if (_readOffset != _writeOffset) return;
    _readOffset = 0;
    _writeOffset = 0;
  }

  void _inputError(Object error, StackTrace stackTrace) {
    _fail(error, stackTrace: stackTrace);
  }

  void _inputDone() {
    if (_failed || _disposed) return;
    if (_state != _stateHeader || _writeOffset != _readOffset) {
      _fail(
        const ScrcpyVideoStreamException(
          'The scrcpy video stream ended in the middle of a frame.',
        ),
      );
      return;
    }
    unawaited(_events.close());
  }

  void _fail(
    Object error, {
    StackTrace? stackTrace,
    bool codecAlreadyCompleted = false,
  }) {
    if (_failed || _disposed) return;
    _failed = true;
    if (!_deviceName.isCompleted) {
      _deviceName.completeError(error, stackTrace);
    }
    if (!codecAlreadyCompleted && !_codecId.isCompleted) {
      _codecId.completeError(error, stackTrace);
    }
    _events.addError(error, stackTrace);
    unawaited(_events.close());
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await _subscription.cancel();
    if (!_deviceName.isCompleted) {
      _deviceName.completeError(
        const ScrcpyVideoStreamException('The video stream was disposed.'),
      );
    }
    if (!_codecId.isCompleted) {
      _codecId.completeError(
        const ScrcpyVideoStreamException('The video stream was disposed.'),
      );
    }
    if (!_events.isClosed) await _events.close();
  }

  static const _stateDeviceName = 0;
  static const _stateCodec = 1;
  static const _stateHeader = 2;
  static const _statePacket = 3;
  static const _configFlag = 1 << 62;
  static const _keyFrameFlag = 1 << 61;
  static const _ptsMask = (1 << 61) - 1;
  static const _maximumPacketBytes = 32 * 1024 * 1024;
  static const _maximumBufferedBytes = 64 * 1024 * 1024;
}
