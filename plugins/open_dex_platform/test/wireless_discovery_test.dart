import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:open_dex_api/open_dex_api.dart';
import 'package:open_dex_platform/open_dex_platform.dart';
import 'package:test/test.dart';

void main() {
  test(
    'queries use each IPv4 interface and closing stops every socket',
    () async {
      final sockets = <_Socket>[];
      final discovery = MdnsWirelessDiscovery(
        interfacesFactory: (type) async => type == InternetAddressType.IPv4
            ? [_Interface(7, '192.0.2.14'), _Interface(9, '198.51.100.8')]
            : [],
        socketFactory:
            (
              host,
              port, {
              reuseAddress = true,
              reusePort = true,
              ttl = 255,
            }) async {
              final socket = _Socket(InternetAddress(host as String));
              sockets.add(socket);
              return socket;
            },
      );
      addTearDown(discovery.stop);
      await discovery.start();
      expect(discovery.current.status, WirelessDiscoveryStatus.ready);
      expect(sockets, hasLength(2));
      expect(sockets[0].options.single.value, [192, 0, 2, 14]);
      expect(sockets[1].options.single.value, [198, 51, 100, 8]);
      expect(sockets.every((s) => s.sent > 0), isTrue);
      await discovery.stop();
      expect(sockets.every((s) => s.closed), isTrue);
      expect(discovery.current.status, WirelessDiscoveryStatus.idle);
    },
  );

  test(
    'a failed multicast join does not leak the partially opened socket',
    () async {
      final socket = _Socket(InternetAddress.anyIPv4)..failJoin = true;
      final discovery = MdnsWirelessDiscovery(
        interfacesFactory: (type) async => type == InternetAddressType.IPv4
            ? [_Interface(7, '192.0.2.14')]
            : [],
        socketFactory: (
          host,
          port, {
          reuseAddress = true,
          reusePort = true,
          ttl = 255,
        }) async => socket,
      );
      addTearDown(discovery.stop);
      await discovery.start();
      expect(discovery.current.status, WirelessDiscoveryStatus.unavailable);
      expect(socket.closed, isTrue);
    },
  );

  test('closing during bind discards and closes the late socket', () async {
    final pending = Completer<RawDatagramSocket>();
    final socket = _Socket(InternetAddress.anyIPv4);
    final discovery = MdnsWirelessDiscovery(
      interfacesFactory: (type) async =>
          type == InternetAddressType.IPv4 ? [_Interface(7, '192.0.2.14')] : [],
      socketFactory: (
        host,
        port, {
        reuseAddress = true,
        reusePort = true,
        ttl = 255,
      }) => pending.future,
    );
    final starting = discovery.start();
    await Future<void>.delayed(Duration.zero);
    await discovery.stop();
    pending.complete(socket);
    await starting;
    expect(socket.closed, isTrue);
    expect(discovery.current.status, WirelessDiscoveryStatus.idle);
  });
}

class _Interface implements NetworkInterface {
  _Interface(this.index, String address) : addresses = [_Address(address)];
  @override
  final int index;
  @override
  final List<InterfaceAddress> addresses;
  @override
  String get name => 'test-$index';
}

class _Address implements InterfaceAddress {
  _Address(String address) : _value = InternetAddress(address);
  final InternetAddress _value;
  @override
  String get address => _value.address;
  @override
  InternetAddressType get type => _value.type;
  @override
  Uint8List get rawAddress => _value.rawAddress;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Socket extends Stream<RawSocketEvent> implements RawDatagramSocket {
  _Socket(this.address);
  @override
  final InternetAddress address;
  final controller = StreamController<RawSocketEvent>();
  final options = <RawSocketOption>[];
  bool failJoin = false;
  bool closed = false;
  int sent = 0;
  @override
  void setRawOption(RawSocketOption option) => options.add(option);
  @override
  void joinMulticast(InternetAddress group, [NetworkInterface? interface]) {
    if (failJoin) {
      throw const SocketException('Synthetic interface disappeared');
    }
  }

  @override
  int send(List<int> bytes, InternetAddress address, int port) {
    sent++;
    return bytes.length;
  }

  @override
  void close() {
    closed = true;
    unawaited(controller.close());
  }

  @override
  StreamSubscription<RawSocketEvent> listen(
    void Function(RawSocketEvent)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) => controller.stream.listen(
    onData,
    onError: onError,
    onDone: onDone,
    cancelOnError: cancelOnError,
  );
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
