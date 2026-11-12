import 'package:flutter_test/flutter_test.dart';
import '../support/heritagebot_test_adapter.dart';

// INT-009 — GPS Location + AI Narrative Generator / Trigger location-based narrative
// Proponent: Reil Esdrelon
// Test description: Trigger location-based narrative
// Expected result: Correct site narrative is offered
// NOTE: Connect the adapter to actual HeritageBot code before recording a PASS.

void main() {
  final adapter = createHeritageBotTestAdapter();

  test('INT-009 - Trigger location-based narrative', () async {
    final scenario = HeritageBotScenario(
      id: 'INT-009',
      kind: 'integration',
      module: 'GPS Location + AI Narrative Generator',
      unit: 'Trigger location-based narrative',
      proponent: 'Reil Esdrelon',
      description: 'Trigger location-based narrative',
      expectedResult: 'Correct site narrative is offered',
      precondition: 'Tourist is within configured radius',
      inputs: const <String, Object?>{
        'fixtureId': 'INT-009',
      },
    );

    // The adapter must execute real app code / observe real UI or backend state.
    final observed = await adapter!.execute(scenario);

      expect(
        observed['heritageSiteDetected'],
        equals(true),
        reason: 'INT-009: heritageSiteDetected does not match the real system result',
      );
      expect(
        observed['correctSiteNarrativeOffered'],
        equals(true),
        reason: 'INT-009: correctSiteNarrativeOffered does not match the real system result',
      );
  }, skip: adapter == null ? 'Not connected to real HeritageBot implementation' : false);
}
