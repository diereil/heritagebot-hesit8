import 'package:flutter_test/flutter_test.dart';
import '../support/heritagebot_test_adapter.dart';

// INT-037 — System Settings + Tourist Language Options / Apply language configuration
// Proponent: AI Knowledge Base / System Team
// Test description: Apply language configuration
// Expected result: Configured language options appear
// NOTE: Connect the adapter to actual HeritageBot code before recording a PASS.

void main() {
  final adapter = createHeritageBotTestAdapter();

  test('INT-037 - Apply language configuration', () async {
    final scenario = HeritageBotScenario(
      id: 'INT-037',
      kind: 'integration',
      module: 'System Settings + Tourist Language Options',
      unit: 'Apply language configuration',
      proponent: 'AI Knowledge Base / System Team',
      description: 'Apply language configuration',
      expectedResult: 'Configured language options appear',
      precondition: 'Admin saves supported languages',
      inputs: const <String, Object?>{
        'fixtureId': 'INT-037',
      },
    );

    // The adapter must execute real app code / observe real UI or backend state.
    final observed = await adapter!.execute(scenario);

      expect(
        observed['languageConfigSaved'],
        equals(true),
        reason: 'INT-037: languageConfigSaved does not match the real system result',
      );
      expect(
        observed['touristOptionsUpdated'],
        equals(true),
        reason: 'INT-037: touristOptionsUpdated does not match the real system result',
      );
  }, skip: adapter == null ? 'Not connected to real HeritageBot implementation' : false);
}
