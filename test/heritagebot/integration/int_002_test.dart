import 'package:flutter_test/flutter_test.dart';
import '../support/heritagebot_test_adapter.dart';

// INT-002 — Authentication + Admin Dashboard / Verify admin login
// Proponent: Reil Esdrelon
// Test description: Verify admin login
// Expected result: Admin dashboard loads with authorized access
// NOTE: Connect the adapter to actual HeritageBot code before recording a PASS.

void main() {
  final adapter = createHeritageBotTestAdapter();

  test('INT-002 - Verify admin login', () async {
    final scenario = HeritageBotScenario(
      id: 'INT-002',
      kind: 'integration',
      module: 'Authentication + Admin Dashboard',
      unit: 'Verify admin login',
      proponent: 'Reil Esdrelon',
      description: 'Verify admin login',
      expectedResult: 'Admin dashboard loads with authorized access',
      precondition: 'Verified admin account',
      inputs: const <String, Object?>{
        'fixtureId': 'INT-002',
      },
    );

    // The adapter must execute real app code / observe real UI or backend state.
    final observed = await adapter!.execute(scenario);

      expect(
        observed['adminAuthorized'],
        equals(true),
        reason: 'INT-002: adminAuthorized does not match the real system result',
      );
      expect(
        observed['adminDashboardLoaded'],
        equals(true),
        reason: 'INT-002: adminDashboardLoaded does not match the real system result',
      );
  }, skip: adapter == null ? 'Not connected to real HeritageBot implementation' : false);
}
