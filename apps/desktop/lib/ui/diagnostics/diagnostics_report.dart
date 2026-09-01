import 'package:open_dex_api/open_dex_api.dart';

/// A paste-ready bug report describing the current session.
///
/// Every performance complaint arrives as "it feels slow", because a person has
/// no way to see what their session was doing, let alone send it. One button
/// turns that into something a maintainer can act on.
///
/// Two rules shape what goes in:
///
/// **Nothing identifying.** This lands in a public issue tracker. The device
/// serial identifies the hardware and diagnoses nothing here, so it is left
/// out; the model and Android version are what actually matter.
///
/// **No invented values.** A measurement the phone did not supply is reported
/// as absent. Printing `0 ms` for a latency nobody measured sends a maintainer
/// after the wrong thing entirely.
String diagnosticsReport({
  required OpenDexSnapshot snapshot,
  required String buildLabel,
  required String platform,
}) {
  final StringBuffer out = StringBuffer('### DroidPier diagnostics\n\n');

  out.writeln('| | |');
  out.writeln('| --- | --- |');
  out.writeln('| Build | $buildLabel |');
  out.writeln('| Desktop | $platform |');

  final DeviceSummary? device = snapshot.selectedDevice;
  if (device == null) {
    out.writeln('| Phone | No phone connected |');
  } else {
    out.writeln('| Phone | ${device.model ?? device.name} |');
    out.writeln('| Android | ${device.androidVersion ?? _unknown} |');
  }

  out.writeln('| Boot | ${snapshot.boot.phase.name} |');
  out.writeln('| Agent | ${snapshot.agentStatus.name} |');
  out.writeln('| Latency | ${_measure(snapshot.telemetry.linkLatency)} |');
  out.writeln('| Throughput | ${_measure(snapshot.telemetry.throughput)} |');

  final String bootMessage = snapshot.boot.message.trim();
  if (bootMessage.isNotEmpty) {
    out.writeln('| Boot message | $bootMessage |');
  }

  out.writeln();

  if (snapshot.windows.isEmpty) {
    out.writeln('No windows open.');
  } else {
    out.writeln('**Windows**');
    out.writeln();
    out.writeln('| App | State | Presented |');
    out.writeln('| --- | --- | --- |');
    for (final WindowSessionState w in snapshot.windows) {
      final double? fps = w.presentedFramesPerSecond;
      out.writeln(
        '| ${w.application.label} | ${w.status.name} | '
        '${fps == null ? _unmeasured : '${fps.toStringAsFixed(1)}/s'} |',
      );
    }
  }

  final List<String> errors = <String>[
    // The code and the capability, never the transcript. `technicalDetails`
    // is built from process exceptions and can carry a serial, an address or
    // a local path, and this report says plainly that nothing identifying
    // goes in it. Putting a raw transcript here would break that promise.
    if (snapshot.boot.error case final OpenDexError e)
      'Boot: ${e.message} (${e.code.name}'
          '${e.capability == null ? '' : ', ${e.capability}'})',
    for (final WindowSessionState w in snapshot.windows)
      if (w.error?.message case final String m) '${w.application.label}: $m',
  ];
  if (errors.isNotEmpty) {
    out.writeln();
    out.writeln('**Errors**');
    out.writeln();
    for (final String e in errors) {
      out.writeln('- $e');
    }
  }

  return out.toString();
}

const String _unknown = 'unknown';
const String _unmeasured = 'not measured';

/// A measurement, or a plain statement that there was not one.
String _measure(TelemetryMeasurement? m) {
  if (m == null) return _unmeasured;
  final String value = m.value == m.value.roundToDouble()
      ? m.value.toStringAsFixed(0)
      : m.value.toStringAsFixed(1);
  return '$value ${_unitLabel(m.unit)}';
}

String _unitLabel(TelemetryUnit unit) => switch (unit) {
  TelemetryUnit.milliseconds => 'ms',
  TelemetryUnit.bytesPerSecond => 'B/s',
  TelemetryUnit.framesPerSecond => '/s',
};
