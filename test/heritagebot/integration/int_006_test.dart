import 'package:flutter_test/flutter_test.dart';
import '../support/heritagebot_test_adapter.dart';

// INT-006 — Forgot Password + Authentication / Complete password reset
// Proponent: Reil Esdrelon
// Test description: Complete password reset
// Expected result: New password permits login
// NOTE: Connect the adapter to actual HeritageBot code before recording a PASS.

void main() {
  final adapter = createHeritageBotTestAdapter();

  test('INT-006 - Complete password reset', () async {
    final scenario = HeritageBotScenario(
      id: 'INT-006',
      kind: 'integration',
      module: 'Forgot Password + Authentication',
      unit: 'Complete password reset',
      proponent: 'Reil Esdrelon',
      description: 'Complete password reset',
      expectedResult: 'New password permits login',
      precondition: 'Registered account and valid reset link',
      inputs: const <String, Object?>{
        'fixtureId': 'INT-006',
      },
    );

    // The adapter must execute real app code / observe real UI or backend state.
    final observed = await adapter!.execute(scenario);

      expect(
        observed['passwordResetComplete'],
        equals(true),
        reason: 'INT-006: passwordResetComplete does not match the real system result',
      );
      expect(
        observed['newPasswordLoginAccepted'],
        equals(true),
        reason: 'INT-006: newPasswordLoginAccepted does not match the real system result',
      );
  }, skip: adapter == null ? 'Not connected to real HeritageBot implementation' : false);
}
