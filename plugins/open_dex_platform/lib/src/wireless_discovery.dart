import 'dart:async';
import 'dart:io';

import 'package:multicast_dns/multicast_dns.dart';
import 'package:open_dex_api/open_dex_api.dart';
import 'package:open_dex_core/open_dex_core.dart';

Future<Iterable<NetworkInterface>> _listInterfaces(InternetAddressType type) =>
    NetworkInterface.list(type: type, includeLinkLocal: true);

/// Local DNS-SD browsing only: no subnet scans or connection attempts.
class MdnsWirelessDiscovery implements WirelessDiscoveryGateway {
  MdnsWirelessDiscovery({
    this._clientFactory,
    this._socketFactory = RawDatagramSocket.bind,
    this._interfacesFactory = _listInterfaces,
  });
  final MDnsClient Function()? _clientFactory;
  final RawDatagramSocketFactory _socketFactory;
  final NetworkInterfacesFactory _interfacesFactory;
  final _updates = StreamController<WirelessDiscoveryState>.broadcast(
    sync: true,
  );
  final _records = <String, WirelessAdvertisement>{};
  final _clients = <(MDnsClient, int, List<RawDatagramSocket>)>[];
  WirelessDiscoveryState _current = const WirelessDiscoveryState();
  Timer? _timer;
  bool _scanning = false;
  bool _active = false;
  int _epoch = 0;
  int _ticks = 0;
  String _network = '';
  @override
  WirelessDiscoveryState get current => _current;
  @override
  Stream<WirelessDiscoveryState> get updates => _updates.stream;

  @override
  Future<void> start() async {
    if (_active) return;
    _active = true;
    final epoch = ++_epoch;
    _publish(WirelessDiscoveryStatus.searching);
    try {
      await _openClients(epoch);
    } on Object {
      if (_active && epoch == _epoch) {
        _publish(WirelessDiscoveryStatus.unavailable);
      }
    }
    if (!_active || epoch != _epoch) return;
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      _records.removeWhere(
        (_, value) => !value.expiresAt.isAfter(DateTime.now()),
      );
      _publish(
        _clients.isEmpty
            ? WirelessDiscoveryStatus.unavailable
            : WirelessDiscoveryStatus.ready,
      );
      if (++_ticks % 4 == 0) unawaited(_scan(epoch));
      if (_ticks % 12 == 0) unawaited(_checkNetwork(epoch));
    });
    unawaited(_scan(epoch));
  }

  Future<List<NetworkInterface>> _interfaces() async {
    return [
      ...await _interfacesFactory(InternetAddressType.IPv4),
      ...await _interfacesFactory(InternetAddressType.IPv6),
    ];
  }

  String _fingerprint(List<NetworkInterface> interfaces) =>
      (interfaces
              .map(
                (i) =>
                    '${i.index}:${i.addresses.map((a) => a.address).join(',')}',
              )
              .toList()
            ..sort())
          .join('|');

  Future<void> _openClients(int epoch) async {
    final interfaces = await _interfaces();
    _network = _fingerprint(interfaces);
    for (final interface in interfaces) {
      if (!_active || epoch != _epoch) return;
      if (interface.addresses.isEmpty) continue;
      final type = interface.addresses.first.type;
      final sockets = <RawDatagramSocket>[];
      final client =
          _clientFactory?.call() ??
          MDnsClient(
            rawDatagramSocketFactory:
                (
                  host,
                  port, {
                  reuseAddress = true,
                  reusePort = true,
                  ttl = 255,
                }) async {
                  final socket = await _socketFactory(
                    host,
                    port,
                    reuseAddress: reuseAddress,
                    reusePort: reusePort,
                    ttl: ttl,
                  );
                  sockets.add(socket);
                  // Joining a group selects where to listen, not where queries leave.
                  // Without this, IPv4 queries only reach the default-route interface.
                  socket.setRawOption(
                    type == InternetAddressType.IPv4
                        ? RawSocketOption(
                            RawSocketOption.levelIPv4,
                            RawSocketOption.IPv4MulticastInterface,
                            interface.addresses.first.rawAddress,
                          )
                        : RawSocketOption.fromInt(
                            RawSocketOption.levelIPv6,
                            RawSocketOption.IPv6MulticastInterface,
                            interface.index,
                          ),
                  );
                  return socket;
                },
          );
      final binding = (client, interface.index, sockets);
      try {
        await client.start(
          listenAddress: type == InternetAddressType.IPv4
              ? InternetAddress.anyIPv4
              : InternetAddress.anyIPv6,
          interfacesFactory: (_) async => [interface],
          onError: (Object _) {
            // Reopen failed listeners on the next network check.
            if (_active && epoch == _epoch) _network = '';
          },
        );
        if (!_active || epoch != _epoch) {
          _closeBinding(binding);
          return;
        }
        _clients.add(binding);
      } on Object {
        _closeBinding(binding);
      }
    }
    _publish(
      _clients.isEmpty
          ? WirelessDiscoveryStatus.unavailable
          : WirelessDiscoveryStatus.ready,
    );
  }

  Future<void> _checkNetwork(int epoch) async {
    try {
      final fingerprint = _fingerprint(await _interfaces());
      if (!_active || epoch != _epoch) return;
      if (fingerprint != _network || _clients.isEmpty) {
        await stop();
        if (_epoch == epoch + 1) await start();
      }
    } on Object {
      /* A network may disappear between enumeration and bind. */
    }
  }

  Future<void> _scan(int epoch) async {
    if (_scanning || !_active || epoch != _epoch) return;
    _scanning = true;
    try {
      await Future.wait([
        for (final binding in _clients.toList())
          for (final kind in WirelessServiceKind.values)
            _browse(binding, kind, epoch),
      ]);
    } finally {
      _scanning = false;
    }
  }

  Future<void> _browse(
    (MDnsClient, int, List<RawDatagramSocket>) binding,
    WirelessServiceKind kind,
    int epoch,
  ) async {
    final service = kind == WirelessServiceKind.pairing
        ? '_adb-tls-pairing._tcp.local'
        : '_adb-tls-connect._tcp.local';
    final resolutions = <Future<void>>[];
    try {
      await for (final ptr in binding.$1.lookup<PtrResourceRecord>(
        ResourceRecordQuery.serverPointer(service),
        timeout: const Duration(seconds: 2),
      )) {
        if (!_active || epoch != _epoch) return;
        if (resolutions.length < 128) {
          resolutions.add(_resolve(binding, ptr, kind, epoch));
        }
      }
      await Future.wait(resolutions);
    } on Object {
      /* Manual pairing remains available when multicast is blocked. */
    }
  }

  Future<void> _resolve(
    (MDnsClient, int, List<RawDatagramSocket>) binding,
    PtrResourceRecord ptr,
    WirelessServiceKind kind,
    int epoch,
  ) async {
    final client = binding.$1;
    try {
      String? displayName;
      final texts = await client
          .lookup<TxtResourceRecord>(
            ResourceRecordQuery.text(ptr.domainName),
            timeout: const Duration(milliseconds: 400),
          )
          .toList();
      for (final txt in texts) {
        for (final line in txt.text.split(RegExp(r'[\n\x00]'))) {
          final split = line.indexOf('=');
          if (split < 0) continue;
          if ([
            'name',
            'product_model',
            'given_name',
          ].contains(line.substring(0, split))) {
            final value = line
                .substring(split + 1)
                .replaceAll(RegExp(r'[\x00-\x1f\x7f]'), '')
                .trim();
            if (value.isNotEmpty && value.length <= 80) displayName = value;
          }
        }
      }
      await for (final srv in client.lookup<SrvResourceRecord>(
        ResourceRecordQuery.service(ptr.domainName),
        timeout: const Duration(seconds: 2),
      )) {
        if (srv.port < 1 || srv.port > 65535) continue;
        for (final query in [
          ResourceRecordQuery.addressIPv4(srv.target),
          ResourceRecordQuery.addressIPv6(srv.target),
        ]) {
          await for (final ip in client.lookup<IPAddressResourceRecord>(
            query,
            timeout: const Duration(milliseconds: 600),
          )) {
            if (!_active || epoch != _epoch) return;
            if (ip.address.isLoopback ||
                ip.address.isMulticast ||
                ip.address.address == '0.0.0.0' ||
                ip.address.address == '::') {
              continue;
            }
            final scope =
                ip.address.type == InternetAddressType.IPv6 &&
                    ip.address.address.toLowerCase().startsWith('fe80:') &&
                    !ip.address.address.contains('%')
                ? '%${binding.$2}'
                : '';
            final expiry = [
              ptr.validUntil,
              srv.validUntil,
              ip.validUntil,
            ].reduce((a, b) => a < b ? a : b);
            final record = WirelessAdvertisement(
              serviceName: ptr.domainName,
              kind: kind,
              host: '${ip.address.address}$scope',
              port: srv.port,
              expiresAt: DateTime.fromMillisecondsSinceEpoch(expiry),
              displayName: displayName,
            );
            if (record.expiresAt.isAfter(DateTime.now())) {
              _records[record.id] = record;
            } else {
              _records.remove(record.id);
            }
            _publish(WirelessDiscoveryStatus.ready);
          }
        }
      }
    } on Object {
      /* Ignore malformed/incomplete advertisements and let existing records expire. */
    }
  }

  void _publish(WirelessDiscoveryStatus status) {
    // One row per advertised service; retain alternative addresses internally.
    final visible = <String, WirelessAdvertisement>{};
    for (final record in _records.values) {
      final key = '${record.kind.name}:${record.serviceName}';
      final previous = visible[key];
      if (previous == null ||
          (previous.host.contains(':') && !record.host.contains(':'))) {
        visible[key] = record;
      }
    }
    _current = WirelessDiscoveryState(
      status: status,
      devices: List.unmodifiable(visible.values),
      message: status == WirelessDiscoveryStatus.unavailable
          ? 'Local discovery is unavailable. Check network permissions or use manual pairing.'
          : null,
    );
    _updates.add(_current);
  }

  @override
  Future<void> stop() async {
    _active = false;
    _epoch++;
    _timer?.cancel();
    _timer = null;
    for (final binding in _clients) {
      _closeBinding(binding);
    }
    _clients.clear();
    _records.clear();
    _publish(WirelessDiscoveryStatus.idle);
  }

  void _closeBinding((MDnsClient, int, List<RawDatagramSocket>) binding) {
    try {
      binding.$1.stop();
    } finally {
      // multicast_dns 0.3.3+1 does not close sockets if start() fails midway.
      // Retain ownership so interface removal and bind errors cannot leak them.
      for (final socket in binding.$3) {
        socket.close();
      }
      binding.$3.clear();
    }
  }
}
