import 'package:flutter_test/flutter_test.dart';
import '../support/heritagebot_test_adapter.dart';

// INT-029 — Heritage Site Management + Tourist Site Directory / Publish updated site details
// Proponent: Shawn Guillmar C. Morales
// Test description: Publish updated site details
// Expected result: Updated site details appear to tourists
// NOTE: Connect the adapter to actual HeritageBot code before recording a PASS.

void main() {
  final adapter = createHeritageBotTestAdapter();

  test('INT-029 - Publish updated site details', () async {
    final scenario = HeritageBotScenario(
      id: 'INT-029',
      kind: 'integration',
      module: 'Heritage Site Management + Tourist Site Directory',
      unit: 'Publish updated site details',
      proponent: 'Shawn Guillmar C. Morales',
      description: 'Publish updated site details',
      expectedResult: 'Updated site details appear to tourists',
      precondition: 'Authorized site update completed',
      inputs: const <String, Object?>{
        'fixtureId': 'INT-029',
      },
    );

    // The adapter must execute real app code / observe real UI or backend state.
    final observed = await adapter!.execute(scenario);

      expect(
        observed['heritageRecordUpdated'],
        equals(true),
        reason: 'INT-029: heritageRecordUpdated does not match the real system result',
      );
      expect(
        observed['touristDirectoryUpdated'],
        equals(true),
        reason: 'INT-029: touristDirectoryUpdated does not match the real system result',
      );
  }, skip: adapter == null ? 'Not connected to real HeritageBot implementation' : false);
}
