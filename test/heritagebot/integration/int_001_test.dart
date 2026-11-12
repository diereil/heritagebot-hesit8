import 'package:flutter_test/flutter_test.dart';
import '../support/heritagebot_test_adapter.dart';

// INT-001 — Authentication + Tourist Home / Verify tourist login
// Proponent: Reil Esdrelon
// Test description: Verify tourist login
// Expected result: Tourist home loads for authenticated tourist
// NOTE: Connect the adapter to actual HeritageBot code before recording a PASS.

void main() {
  final adapter = createHeritageBotTestAdapter();

  test('INT-001 - Verify tourist login', () async {
    final scenario = HeritageBotScenario(
      id: 'INT-001',
      kind: 'integration',
      module: 'Authentication + Tourist Home',
      unit: 'Verify tourist login',
      proponent: 'Reil Esdrelon',
      description: 'Verify tourist login',
      expectedResult: 'Tourist home loads for authenticated tourist',
      precondition: 'Verified tourist account',
      inputs: const <String, Object?>{
        'fixtureId': 'INT-001',
      },
    );

    // The adapter must execute real app code / observe real UI or backend state.
    final observed = await adapter!.execute(scenario);

      expect(
        observed['authenticated'],
        equals(true),
        reason: 'INT-001: authenticated does not match the real system result',
      );
      expect(
        observed['touristHomeLoaded'],
        equals(true),
        reason: 'INT-001: touristHomeLoaded does not match the real system result',
      );
  }, skip: adapter == null ? 'Not connected to real HeritageBot implementation' : false);
}
