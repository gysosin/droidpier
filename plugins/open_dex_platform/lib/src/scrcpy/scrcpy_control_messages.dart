import 'dart:convert';
import 'dart:typed_data';

enum ScrcpyKeyAction { down, up }

enum ScrcpyTouchAction { down, up, move, cancel }

abstract final class ScrcpyControlMessages {
  static Uint8List injectKey({
    required ScrcpyKeyAction action,
    required int keycode,
    int repeat = 0,
    int metaState = 0,
  }) {
    final message = _message(14);
    message.setUint8(0, 0);
    message.setUint8(1, action.index);
    message.setUint32(2, keycode, Endian.big);
    message.setUint32(6, repeat, Endian.big);
    message.setUint32(10, metaState, Endian.big);
    return message.buffer.asUint8List();
  }

  static Uint8List injectText(String text) {
    final encoded = utf8.encode(text);
    if (encoded.length > 300) {
      throw ArgumentError.value(
        text,
        'text',
        'must be at most 300 UTF-8 bytes',
      );
    }
    final message = _message(5 + encoded.length);
    message.setUint8(0, 1);
    message.setUint32(1, encoded.length, Endian.big);
    message.buffer.asUint8List().setRange(5, 5 + encoded.length, encoded);
    return message.buffer.asUint8List();
  }

  static Uint8List injectTouch({
    required ScrcpyTouchAction action,
    required int x,
    required int y,
    required int screenWidth,
    required int screenHeight,
    int pointerId = genericFingerPointerId,
    int actionButton = 0,
    int buttons = 0,
  }) {
    _validateScreenSize(screenWidth, screenHeight);
    final message = _message(32);
    message.setUint8(0, 2);
    message.setUint8(1, action.index);
    message.setUint64(2, pointerId, Endian.big);
    message.setInt32(10, x, Endian.big);
    message.setInt32(14, y, Endian.big);
    message.setUint16(18, screenWidth, Endian.big);
    message.setUint16(20, screenHeight, Endian.big);
    message.setUint16(
      22,
      action == ScrcpyTouchAction.up || action == ScrcpyTouchAction.cancel
          ? 0
          : 0xffff,
      Endian.big,
    );
    message.setUint32(24, actionButton, Endian.big);
    message.setUint32(28, buttons, Endian.big);
    return message.buffer.asUint8List();
  }

  static Uint8List injectScroll({
    required int x,
    required int y,
    required int screenWidth,
    required int screenHeight,
    required double horizontal,
    required double vertical,
    int buttons = 0,
  }) {
    _validateScreenSize(screenWidth, screenHeight);
    final message = _message(21);
    message.setUint8(0, 3);
    message.setInt32(1, x, Endian.big);
    message.setInt32(5, y, Endian.big);
    message.setUint16(9, screenWidth, Endian.big);
    message.setUint16(11, screenHeight, Endian.big);
    message.setInt16(13, _scrollFixed(horizontal), Endian.big);
    message.setInt16(15, _scrollFixed(vertical), Endian.big);
    message.setUint32(17, buttons, Endian.big);
    return message.buffer.asUint8List();
  }

  static Uint8List getClipboard() => Uint8List.fromList(const [8, 0]);

  static Uint8List setClipboard({
    required int sequence,
    required String text,
    bool paste = false,
  }) {
    final encoded = utf8.encode(text);
    if (encoded.length > _maximumClipboardBytes) {
      throw ArgumentError.value(
        text,
        'text',
        'must be at most $_maximumClipboardBytes UTF-8 bytes',
      );
    }
    final message = _message(14 + encoded.length);
    message.setUint8(0, 9);
    message.setUint64(1, sequence, Endian.big);
    message.setUint8(9, paste ? 1 : 0);
    message.setUint32(10, encoded.length, Endian.big);
    message.buffer.asUint8List().setRange(14, 14 + encoded.length, encoded);
    return message.buffer.asUint8List();
  }

  static Uint8List startApp(String name) {
    final encoded = utf8.encode(name);
    if (encoded.isEmpty || encoded.length > 255) {
      throw ArgumentError.value(
        name,
        'name',
        'must contain between 1 and 255 UTF-8 bytes',
      );
    }
    return Uint8List.fromList([16, encoded.length, ...encoded]);
  }

  static Uint8List resetVideo() => Uint8List.fromList(const [17]);

  static Uint8List resizeDisplay(int width, int height) {
    _validateScreenSize(width, height);
    final message = _message(5);
    message.setUint8(0, 21);
    message.setUint16(1, width, Endian.big);
    message.setUint16(3, height, Endian.big);
    return message.buffer.asUint8List();
  }

  static ByteData _message(int length) => ByteData(length);

  static int _scrollFixed(double value) {
    if (!value.isFinite) {
      throw ArgumentError.value(value, 'scroll', 'must be finite');
    }
    return ((value / 16) * 32768).round().clamp(-32768, 32767);
  }

  static void _validateScreenSize(int width, int height) {
    if (width < 1 || width > 65535 || height < 1 || height > 65535) {
      throw ArgumentError('The video size must fit unsigned 16-bit fields.');
    }
  }

  static const genericFingerPointerId = 0xfffffffffffffffe;
  static const _maximumClipboardBytes = 1024 * 1024;
}
