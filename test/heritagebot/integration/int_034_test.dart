import 'package:flutter_test/flutter_test.dart';
import '../support/heritagebot_test_adapter.dart';

// INT-034 — Administrator Dashboard + System Database / Aggregate account and site counts
// Proponent: James Stephen O. Ramos
// Test description: Aggregate account and site counts
// Expected result: Summary metrics match database
// NOTE: Connect the adapter to actual HeritageBot code before recording a PASS.

void main() {
  final adapter = createHeritageBotTestAdapter();

  test('INT-034 - Aggregate account and site counts', () async {
    final scenario = HeritageBotScenario(
      id: 'INT-034',
      kind: 'integration',
      module: 'Administrator Dashboard + System Database',
      unit: 'Aggregate account and site counts',
      proponent: 'James Stephen O. Ramos',
      description: 'Aggregate account and site counts',
      expectedResult: 'Summary metrics match database',
      precondition: 'Records exist',
      inputs: const <String, Object?>{
        'fixtureId': 'INT-034',
      },
    );

    // The adapter must execute real app code / observe real UI or backend state.
    final observed = await adapter!.execute(scenario);

      expect(
        observed['summaryCalculated'],
        equals(true),
        reason: 'INT-034: summaryCalculated does not match the real system result',
      );
      expect(
        observed['summaryMatchesStoredRecords'],
        equals(true),
        reason: 'INT-034: summaryMatchesStoredRecords does not match the real system result',
      );
  }, skip: adapter == null ? 'Not connected to real HeritageBot implementation' : false);
}
