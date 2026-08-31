import 'package:flutter_test/flutter_test.dart';
import 'package:open_android_dex/bootstrap/probe_display_report.dart';

void main() {
  test('parses the matching probe display report from adb logcat', () {
    const output = '''
I/OpenDexStreamProbe(1200): report_id=old display_id=9 refresh_hz=90.0
I/OpenDexStreamProbe(1200): report_id=bench_42 display_id=317 refresh_hz=60.000004
''';

    expect(
      parseProbeDisplayReport(output, reportId: 'bench_42'),
      const ProbeDisplayReport(displayId: 317, refreshHz: 60.000004),
    );
  });

  test('ignores malformed and unrelated reports', () {
    const output = '''
I/OpenDexStreamProbe(1200): report_id=bench_41 display_id=317 refresh_hz=60.0
I/OpenDexStreamProbe(1200): report_id=bench_42 display_id=-1 refresh_hz=0.0
''';

    expect(parseProbeDisplayReport(output, reportId: 'bench_42'), isNull);
  });
}
