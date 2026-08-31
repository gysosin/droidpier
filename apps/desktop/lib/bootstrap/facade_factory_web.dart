import 'package:open_dex_api/open_dex_api.dart';
import 'package:open_dex_core/open_dex_core.dart';

OpenDexFacade createFacade() => MockOpenDexFacade(
  scenario: _scenarioFromEnvironment() ?? MockScenario.disconnected,
);

OpenDexFacade createBenchmarkFacade({
  required List<AndroidApplication> additionalApplications,
  required Future<void> Function(DeviceSummary device, int displayId)
  onDisplayCreated,
}) => createFacade();

MockScenario? _scenarioFromEnvironment() {
  const name = String.fromEnvironment('OPEN_DEX_SCENARIO');
  if (name.isEmpty) return null;
  for (final scenario in MockScenario.values) {
    if (scenario.name == name) return scenario;
  }
  return MockScenario.disconnected;
}
