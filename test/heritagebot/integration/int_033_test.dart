import 'package:flutter_test/flutter_test.dart';
import '../support/heritagebot_test_adapter.dart';

// INT-033 — User Profile + Protected Screens / End authenticated session
// Proponent: James Stephen O. Ramos
// Test description: End authenticated session
// Expected result: Protected screens require reauthentication
// NOTE: Connect the adapter to actual HeritageBot code before recording a PASS.

void main() {
  final adapter = createHeritageBotTestAdapter();

  test('INT-033 - End authenticated session', () async {
    final scenario = HeritageBotScenario(
      id: 'INT-033',
      kind: 'integration',
      module: 'User Profile + Protected Screens',
      unit: 'End authenticated session',
      proponent: 'James Stephen O. Ramos',
      description: 'End authenticated session',
      expectedResult: 'Protected screens require reauthentication',
      precondition: 'User logs out',
      inputs: const <String, Object?>{
        'fixtureId': 'INT-033',
      },
    );

    // The adapter must execute real app code / observe real UI or backend state.
    final observed = await adapter!.execute(scenario);

      expect(
        observed['sessionEnded'],
        equals(true),
        reason: 'INT-033: sessionEnded does not match the real system result',
      );
      expect(
        observed['protectedScreensRequireLogin'],
        equals(true),
        reason: 'INT-033: protectedScreensRequireLogin does not match the real system result',
      );
  }, skip: adapter == null ? 'Not connected to real HeritageBot implementation' : false);
}
