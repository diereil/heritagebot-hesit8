import 'package:flutter_test/flutter_test.dart';
import '../support/heritagebot_test_adapter.dart';

// INT-028 — Admin User Management + User Database / Inspect account details
// Proponent: Shawn Guillmar C. Morales
// Test description: Inspect account details
// Expected result: Correct account data is displayed
// NOTE: Connect the adapter to actual HeritageBot code before recording a PASS.

void main() {
  final adapter = createHeritageBotTestAdapter();

  test('INT-028 - Inspect account details', () async {
    final scenario = HeritageBotScenario(
      id: 'INT-028',
      kind: 'integration',
      module: 'Admin User Management + User Database',
      unit: 'Inspect account details',
      proponent: 'Shawn Guillmar C. Morales',
      description: 'Inspect account details',
      expectedResult: 'Correct account data is displayed',
      precondition: 'Admin is authenticated',
      inputs: const <String, Object?>{
        'fixtureId': 'INT-028',
      },
    );

    // The adapter must execute real app code / observe real UI or backend state.
    final observed = await adapter!.execute(scenario);

      expect(
        observed['userDetailsRetrieved'],
        equals(true),
        reason: 'INT-028: userDetailsRetrieved does not match the real system result',
      );
      expect(
        observed['adminAuthorized'],
        equals(true),
        reason: 'INT-028: adminAuthorized does not match the real system result',
      );
  }, skip: adapter == null ? 'Not connected to real HeritageBot implementation' : false);
}
