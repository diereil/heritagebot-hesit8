import 'package:flutter_test/flutter_test.dart';
import '../support/heritagebot_test_adapter.dart';

// INT-021 — Contributor Profile + Community Story Database / Submit heritage story
// Proponent: James Stephen O. Ramos
// Test description: Submit heritage story
// Expected result: Pending submission is stored
// NOTE: Connect the adapter to actual HeritageBot code before recording a PASS.

void main() {
  final adapter = createHeritageBotTestAdapter();

  test('INT-021 - Submit heritage story', () async {
    final scenario = HeritageBotScenario(
      id: 'INT-021',
      kind: 'integration',
      module: 'Contributor Profile + Community Story Database',
      unit: 'Submit heritage story',
      proponent: 'James Stephen O. Ramos',
      description: 'Submit heritage story',
      expectedResult: 'Pending submission is stored',
      precondition: 'Authenticated contributor and valid story',
      inputs: const <String, Object?>{
        'fixtureId': 'INT-021',
      },
    );

    // The adapter must execute real app code / observe real UI or backend state.
    final observed = await adapter!.execute(scenario);

      expect(
        observed['submissionStored'],
        equals(true),
        reason: 'INT-021: submissionStored does not match the real system result',
      );
      expect(
        observed['submissionStatus'],
        equals('pending'),
        reason: 'INT-021: submissionStatus does not match the real system result',
      );
  }, skip: adapter == null ? 'Not connected to real HeritageBot implementation' : false);
}
