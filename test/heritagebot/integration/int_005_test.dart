import 'package:flutter_test/flutter_test.dart';
import '../support/heritagebot_test_adapter.dart';

// INT-005 — Google Sign-In + Role-Based Navigation / Authenticate using Google
// Proponent: Reil Esdrelon
// Test description: Authenticate using Google
// Expected result: Correct role-specific page opens
// NOTE: Connect the adapter to actual HeritageBot code before recording a PASS.

void main() {
  final adapter = createHeritageBotTestAdapter();

  test('INT-005 - Authenticate using Google', () async {
    final scenario = HeritageBotScenario(
      id: 'INT-005',
      kind: 'integration',
      module: 'Google Sign-In + Role-Based Navigation',
      unit: 'Authenticate using Google',
      proponent: 'Reil Esdrelon',
      description: 'Authenticate using Google',
      expectedResult: 'Correct role-specific page opens',
      precondition: 'Valid Google account',
      inputs: const <String, Object?>{
        'fixtureId': 'INT-005',
      },
    );

    // The adapter must execute real app code / observe real UI or backend state.
    final observed = await adapter!.execute(scenario);

      expect(
        observed['googleAuthenticated'],
        equals(true),
        reason: 'INT-005: googleAuthenticated does not match the real system result',
      );
      expect(
        observed['correctRolePageOpened'],
        equals(true),
        reason: 'INT-005: correctRolePageOpened does not match the real system result',
      );
  }, skip: adapter == null ? 'Not connected to real HeritageBot implementation' : false);
}
