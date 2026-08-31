import 'wireless.dart';

enum OpenDexErrorCode {
  adbUnavailable,
  deviceUnauthorized,
  deviceOffline,
  multipleDevices,
  connectionFailed,
  deploymentFailed,
  permissionDenied,
  capabilityUnavailable,
  protocolError,
  timeout,
  cancelled,
  internal,
}

class OpenDexError {
  const OpenDexError({
    required this.code,
    required this.message,
    this.retryable = false,
    this.capability,
    this.technicalDetails,
    this.wirelessReason,
  });

  final OpenDexErrorCode code;
  final String message;
  final bool retryable;
  final String? capability;
  final WirelessFailureReason? wirelessReason;

  /// Diagnostic information for logs. UI must not display this directly.
  final String? technicalDetails;
}

sealed class CommandResult<T> {
  const CommandResult();

  bool get isSuccess => this is CommandSuccess<T>;
}

final class CommandSuccess<T> extends CommandResult<T> {
  const CommandSuccess(this.value);

  final T value;
}

final class CommandFailure<T> extends CommandResult<T> {
  const CommandFailure(this.error);

  final OpenDexError error;
}

typedef VoidResult = CommandResult<void>;
