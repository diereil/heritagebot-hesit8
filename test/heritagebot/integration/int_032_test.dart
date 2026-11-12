import 'package:flutter_test/flutter_test.dart';
import '../support/heritagebot_test_adapter.dart';

// INT-032 — User Profile + Narrative Translation / Save language preference
// Proponent: James Stephen O. Ramos
// Test description: Save language preference
// Expected result: Preferred language is applied
// NOTE: Connect the adapter to actual HeritageBot code before recording a PASS.

void main() {
  final adapter = createHeritageBotTestAdapter();

  test('INT-032 - Save language preference', () async {
    final scenario = HeritageBotScenario(
      id: 'INT-032',
      kind: 'integration',
      module: 'User Profile + Narrative Translation',
      unit: 'Save language preference',
      proponent: 'James Stephen O. Ramos',
      description: 'Save language preference',
      expectedResult: 'Preferred language is applied',
      precondition: 'Supported language selected',
      inputs: const <String, Object?>{
        'fixtureId': 'INT-032',
      },
    );

    // The adapter must execute real app code / observe real UI or backend state.
    final observed = await adapter!.execute(scenario);

      expect(
        observed['languagePreferenceStored'],
        equals(true),
        reason: 'INT-032: languagePreferenceStored does not match the real system result',
      );
      expect(
        observed['translationUsesPreference'],
        equals(true),
        reason: 'INT-032: translationUsesPreference does not match the real system result',
      );
  }, skip: adapter == null ? 'Not connected to real HeritageBot implementation' : false);
}
