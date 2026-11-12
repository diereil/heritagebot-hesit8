import 'package:flutter_test/flutter_test.dart';
import '../support/heritagebot_test_adapter.dart';

// INT-015 — AI Narrative Generator + Language Service / Translate generated narrative
// Proponent: Reil Esdrelon
// Test description: Translate generated narrative
// Expected result: Translated narrative is displayed
// NOTE: Connect the adapter to actual HeritageBot code before recording a PASS.

void main() {
  final adapter = createHeritageBotTestAdapter();

  test('INT-015 - Translate generated narrative', () async {
    final scenario = HeritageBotScenario(
      id: 'INT-015',
      kind: 'integration',
      module: 'AI Narrative Generator + Language Service',
      unit: 'Translate generated narrative',
      proponent: 'Reil Esdrelon',
      description: 'Translate generated narrative',
      expectedResult: 'Translated narrative is displayed',
      precondition: 'Narrative and supported language available',
      inputs: const <String, Object?>{
        'fixtureId': 'INT-015',
      },
    );

    // The adapter must execute real app code / observe real UI or backend state.
    final observed = await adapter!.execute(scenario);

      expect(
        observed['translationCompleted'],
        equals(true),
        reason: 'INT-015: translationCompleted does not match the real system result',
      );
      expect(
        observed['selectedLanguageDisplayed'],
        equals(true),
        reason: 'INT-015: selectedLanguageDisplayed does not match the real system result',
      );
  }, skip: adapter == null ? 'Not connected to real HeritageBot implementation' : false);
}
