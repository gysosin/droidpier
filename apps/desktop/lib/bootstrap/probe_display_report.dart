class ProbeDisplayReport {
  const ProbeDisplayReport({required this.displayId, required this.refreshHz});

  final int displayId;
  final double refreshHz;

  @override
  bool operator ==(Object other) =>
      other is ProbeDisplayReport &&
      other.displayId == displayId &&
      other.refreshHz == refreshHz;

  @override
  int get hashCode => Object.hash(displayId, refreshHz);
}

final _reportPattern = RegExp(
  r'report_id=([^\s]+) display_id=(-?\d+) refresh_hz=([0-9]+(?:\.[0-9]+)?)',
);

ProbeDisplayReport? parseProbeDisplayReport(
  String logcatOutput, {
  required String reportId,
}) {
  for (final match
      in _reportPattern.allMatches(logcatOutput).toList().reversed) {
    if (match.group(1) != reportId) continue;
    final displayId = int.tryParse(match.group(2)!);
    final refreshHz = double.tryParse(match.group(3)!);
    if (displayId == null ||
        displayId < 0 ||
        refreshHz == null ||
        refreshHz <= 0) {
      return null;
    }
    return ProbeDisplayReport(displayId: displayId, refreshHz: refreshHz);
  }
  return null;
}
