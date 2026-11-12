import 'package:flutter_test/flutter_test.dart';
import '../support/heritagebot_test_adapter.dart';

// INT-004 — Role Selection + Contributor Profile / Register contributor account
// Proponent: Reil Esdrelon
// Test description: Register contributor account
// Expected result: Contributor profile is available
// NOTE: Connect the adapter to actual HeritageBot code before recording a PASS.

void main() {
  final adapter = createHeritageBotTestAdapter();

  test('INT-004 - Register contributor account', () async {
    final scenario = HeritageBotScenario(
      id: 'INT-004',
      kind: 'integration',
      module: 'Role Selection + Contributor Profile',
      unit: 'Register contributor account',
      proponent: 'Reil Esdrelon',
      description: 'Register contributor account',
      expectedResult: 'Contributor profile is available',
      precondition: 'Contributor role selected',
      inputs: const <String, Object?>{
        'fixtureId': 'INT-004',
      },
    );

    // The adapter must execute real app code / observe real UI or backend state.
    final observed = await adapter!.execute(scenario);

      expect(
        observed['contributorRoleSaved'],
        equals(true),
        reason: 'INT-004: contributorRoleSaved does not match the real system result',
      );
      expect(
        observed['contributorProfileLoaded'],
        equals(true),
        reason: 'INT-004: contributorProfileLoaded does not match the real system result',
      );
  }, skip: adapter == null ? 'Not connected to real HeritageBot implementation' : false);
}
