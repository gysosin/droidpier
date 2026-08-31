import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_dex_texture/open_dex_texture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('open_dex_texture');

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('stats decodes every native frame statistic', () async {
    MethodCall? received;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          received = call;
          return <String, int>{
            'frames': 601,
            'presentedFrames': 590,
            'lastFrameMonotonicUs': 123456789,
            'centerLuma': 91,
            'probeLuma': 255,
            'droppedFrames': 3,
          };
        });

    final stats = await const OpenDexTexture().stats(42);

    expect(received?.method, 'stats');
    expect(received?.arguments, <String, int>{'textureId': 42});
    expect(stats.frames, 601);
    expect(stats.presentedFrames, 590);
    expect(stats.lastFrameMonotonicUs, 123456789);
    expect(stats.centerLuma, 91);
    expect(stats.probeLuma, 255);
    expect(stats.droppedFrames, 3);
  });
}
