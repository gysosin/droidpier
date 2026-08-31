import 'dart:convert';

class ProtocolException implements Exception {
  const ProtocolException(this.message);

  final String message;

  @override
  String toString() => 'ProtocolException: $message';
}

class ProtocolEnvelope {
  const ProtocolEnvelope({
    required this.id,
    required this.type,
    required this.timestamp,
    this.data = const {},
    this.version = currentVersion,
  });

  static const int currentVersion = 1;

  final int version;
  final String id;
  final String type;
  final DateTime timestamp;
  final Map<String, Object?> data;

  Map<String, Object?> toJson() => {
    'v': version,
    'id': id,
    'type': type,
    'timestamp': timestamp.toUtc().toIso8601String(),
    'data': data,
  };

  String encode() => jsonEncode(toJson());

  factory ProtocolEnvelope.decode(String source) {
    final dynamic decoded;
    try {
      decoded = jsonDecode(source);
    } on FormatException catch (error) {
      throw ProtocolException('Invalid JSON: ${error.message}');
    }
    if (decoded is! Map<String, dynamic>) {
      throw const ProtocolException('Envelope must be a JSON object.');
    }

    final version = decoded['v'];
    final id = decoded['id'];
    final type = decoded['type'];
    final timestamp = decoded['timestamp'];
    final data = decoded['data'];
    if (version != currentVersion) {
      throw ProtocolException('Unsupported protocol version: $version');
    }
    if (id is! String || id.isEmpty || type is! String || type.isEmpty) {
      throw const ProtocolException(
        'Envelope id and type must be non-empty strings.',
      );
    }
    if (timestamp is! String || DateTime.tryParse(timestamp) == null) {
      throw const ProtocolException('Envelope timestamp must be ISO-8601.');
    }
    if (data is! Map<String, dynamic>) {
      throw const ProtocolException('Envelope data must be a JSON object.');
    }

    return ProtocolEnvelope(
      version: version as int,
      id: id,
      type: type,
      timestamp: DateTime.parse(timestamp),
      data: Map<String, Object?>.from(data),
    );
  }
}
