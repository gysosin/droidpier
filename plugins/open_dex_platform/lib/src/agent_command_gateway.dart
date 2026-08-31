import 'dart:async';

import 'package:open_dex_api/open_dex_api.dart';
import 'package:open_dex_core/open_dex_core.dart';
import 'package:open_dex_protocol/open_dex_protocol.dart';

import 'android_boot_components.dart';

class AgentCommandGateway implements DeviceCommandGateway, PermissionGateway {
  AgentCommandGateway(this.agent);

  final AgentBootComponent agent;

  @override
  Future<void> setVolume(String stream, int value) async {
    if (!_volumeStreams.contains(stream) || value < 0 || value > 100) {
      throw _unavailable('That volume setting is unavailable.', 'volume');
    }
    await _send('volume.set', {'stream': stream, 'value': value});
  }

  @override
  Future<void> sendMediaAction(MediaAction action) =>
      _send('media.action', {'action': action.name});

  @override
  Future<void> setDeviceControl(DeviceControl control, bool enabled) async {
    if (!_supportedControls.contains(control)) {
      throw _unavailable(
        'That device control is not supported without additional permission.',
        'device.${control.name}',
      );
    }
    await _send('device.control', {
      'control': control.name,
      'enabled': enabled,
    });
  }

  @override
  Future<void> openSettings(String capability) async {
    if (capability != 'notifications') {
      throw _unavailable(
        'That permission settings screen is unavailable.',
        'permission-settings',
      );
    }
    await _send('permission.settings', {'capability': capability});
  }

  Future<void> _send(String type, Map<String, Object?> data) async {
    if (!agent.capabilities.contains(type)) {
      throw _unavailable(
        'The connected Android agent does not support this command.',
        type,
      );
    }
    try {
      final response = await agent.request(type, data: data);
      if (response.data['success'] != true) {
        throw const ProtocolException('Android command returned a failure.');
      }
    } on BackendFailure {
      rethrow;
    } on TimeoutException catch (error) {
      throw BackendFailure(
        OpenDexError(
          code: OpenDexErrorCode.timeout,
          message: 'The Android command did not respond in time.',
          retryable: true,
          capability: type,
          technicalDetails: error.toString(),
        ),
      );
    } on ProtocolException catch (error) {
      if (!agent.isAvailable) {
        throw BackendFailure(
          OpenDexError(
            code: OpenDexErrorCode.connectionFailed,
            message: 'The Android agent is reconnecting.',
            retryable: true,
            capability: type,
            technicalDetails: error.toString(),
          ),
        );
      }
      throw BackendFailure(
        OpenDexError(
          code: OpenDexErrorCode.protocolError,
          message: 'The Android command was rejected.',
          capability: type,
          technicalDetails: error.toString(),
        ),
      );
    } on Object catch (error) {
      throw BackendFailure(
        OpenDexError(
          code: OpenDexErrorCode.protocolError,
          message: 'The Android command could not be completed.',
          retryable: true,
          capability: type,
          technicalDetails: error.toString(),
        ),
      );
    }
  }

  static const _volumeStreams = {
    'voiceCall',
    'system',
    'ring',
    'music',
    'alarm',
    'notification',
  };

  static const _supportedControls = {
    DeviceControl.wifi,
    DeviceControl.bluetooth,
    DeviceControl.rotationLock,
    DeviceControl.airplaneMode,
    DeviceControl.mobileData,
    DeviceControl.location,
  };

  static BackendFailure _unavailable(String message, String capability) =>
      BackendFailure(
        OpenDexError(
          code: OpenDexErrorCode.capabilityUnavailable,
          message: message,
          capability: capability,
        ),
      );
}
