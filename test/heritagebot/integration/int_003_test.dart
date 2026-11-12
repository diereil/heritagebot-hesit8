import 'package:flutter_test/flutter_test.dart';
import '../support/heritagebot_test_adapter.dart';

// INT-003 — Sign Up + Email Verification / Create new account and verify email
// Proponent: Reil Esdrelon
// Test description: Create new account and verify email
// Expected result: Verification updates registered account
// NOTE: Connect the adapter to actual HeritageBot code before recording a PASS.

void main() {
  final adapter = createHeritageBotTestAdapter();

  test('INT-003 - Create new account and verify email', () async {
    final scenario = HeritageBotScenario(
      id: 'INT-003',
      kind: 'integration',
      module: 'Sign Up + Email Verification',
      unit: 'Create new account and verify email',
      proponent: 'Reil Esdrelon',
      description: 'Create new account and verify email',
      expectedResult: 'Verification updates registered account',
      precondition: 'Valid registration details',
      inputs: const <String, Object?>{
        'fixtureId': 'INT-003',
      },
    );

    // The adapter must execute real app code / observe real UI or backend state.
    final observed = await adapter!.execute(scenario);

      expect(
        observed['registrationSaved'],
        equals(true),
        reason: 'INT-003: registrationSaved does not match the real system result',
      );
      expect(
        observed['emailVerified'],
        equals(true),
        reason: 'INT-003: emailVerified does not match the real system result',
      );
  }, skip: adapter == null ? 'Not connected to real HeritageBot implementation' : false);
}
