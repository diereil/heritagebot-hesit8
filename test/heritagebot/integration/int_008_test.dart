import 'package:flutter_test/flutter_test.dart';
import '../support/heritagebot_test_adapter.dart';

// INT-008 — GPS Location + Heritage Site Coordinates / Detect proximity to heritage site
// Proponent: Reil Esdrelon
// Test description: Detect proximity to heritage site
// Expected result: Nearby site is correctly identified
// NOTE: Connect the adapter to actual HeritageBot code before recording a PASS.

void main() {
  final adapter = createHeritageBotTestAdapter();

  test('INT-008 - Detect proximity to heritage site', () async {
    final scenario = HeritageBotScenario(
      id: 'INT-008',
      kind: 'integration',
      module: 'GPS Location + Heritage Site Coordinates',
      unit: 'Detect proximity to heritage site',
      proponent: 'Reil Esdrelon',
      description: 'Detect proximity to heritage site',
      expectedResult: 'Nearby site is correctly identified',
      precondition: 'Location permission and valid coordinates',
      inputs: const <String, Object?>{
        'fixtureId': 'INT-008',
      },
    );

    // The adapter must execute real app code / observe real UI or backend state.
    final observed = await adapter!.execute(scenario);

      expect(
        observed['nearbySiteDetected'],
        equals(true),
        reason: 'INT-008: nearbySiteDetected does not match the real system result',
      );
      expect(
        observed['correctCoordinatesUsed'],
        equals(true),
        reason: 'INT-008: correctCoordinatesUsed does not match the real system result',
      );
  }, skip: adapter == null ? 'Not connected to real HeritageBot implementation' : false);
}
