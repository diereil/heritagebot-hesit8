import 'package:flutter_test/flutter_test.dart';
import '../support/heritagebot_test_adapter.dart';

// INT-040 — Location Permissions + Interactive Map / Handle denied location access
// Proponent: Reil Esdrelon
// Test description: Handle denied location access
// Expected result: Permission guidance appears without crash
// NOTE: Connect the adapter to actual HeritageBot code before recording a PASS.

void main() {
  final adapter = createHeritageBotTestAdapter();

  test('INT-040 - Handle denied location access', () async {
    final scenario = HeritageBotScenario(
      id: 'INT-040',
      kind: 'integration',
      module: 'Location Permissions + Interactive Map',
      unit: 'Handle denied location access',
      proponent: 'Reil Esdrelon',
      description: 'Handle denied location access',
      expectedResult: 'Permission guidance appears without crash',
      precondition: 'Location permission denied',
      inputs: const <String, Object?>{
        'fixtureId': 'INT-040',
      },
    );

    // The adapter must execute real app code / observe real UI or backend state.
    final observed = await adapter!.execute(scenario);

      expect(
        observed['permissionGuidanceVisible'],
        equals(true),
        reason: 'INT-040: permissionGuidanceVisible does not match the real system result',
      );
      expect(
        observed['mapDidNotCrash'],
        equals(true),
        reason: 'INT-040: mapDidNotCrash does not match the real system result',
      );
  }, skip: adapter == null ? 'Not connected to real HeritageBot implementation' : false);
}
