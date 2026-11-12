import 'package:flutter_test/flutter_test.dart';
import '../support/heritagebot_test_adapter.dart';

// INT-030 — Heritage Coordinates + Geolocation Detection / Update site detection location
// Proponent: Shawn Guillmar C. Morales
// Test description: Update site detection location
// Expected result: Detection uses updated coordinates
// NOTE: Connect the adapter to actual HeritageBot code before recording a PASS.

void main() {
  final adapter = createHeritageBotTestAdapter();

  test('INT-030 - Update site detection location', () async {
    final scenario = HeritageBotScenario(
      id: 'INT-030',
      kind: 'integration',
      module: 'Heritage Coordinates + Geolocation Detection',
      unit: 'Update site detection location',
      proponent: 'Shawn Guillmar C. Morales',
      description: 'Update site detection location',
      expectedResult: 'Detection uses updated coordinates',
      precondition: 'Valid new site coordinates saved',
      inputs: const <String, Object?>{
        'fixtureId': 'INT-030',
      },
    );

    // The adapter must execute real app code / observe real UI or backend state.
    final observed = await adapter!.execute(scenario);

      expect(
        observed['coordinatesUpdated'],
        equals(true),
        reason: 'INT-030: coordinatesUpdated does not match the real system result',
      );
      expect(
        observed['newCoordinatesUsedByDetection'],
        equals(true),
        reason: 'INT-030: newCoordinatesUsedByDetection does not match the real system result',
      );
  }, skip: adapter == null ? 'Not connected to real HeritageBot implementation' : false);
}
