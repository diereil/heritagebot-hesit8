import 'package:flutter_test/flutter_test.dart';
import '../support/heritagebot_test_adapter.dart';

// INT-024 — Review Status + Contributor Dashboard / Show administrator decision
// Proponent: James Stephen O. Ramos
// Test description: Show administrator decision
// Expected result: Current decision is visible
// NOTE: Connect the adapter to actual HeritageBot code before recording a PASS.

void main() {
  final adapter = createHeritageBotTestAdapter();

  test('INT-024 - Show administrator decision', () async {
    final scenario = HeritageBotScenario(
      id: 'INT-024',
      kind: 'integration',
      module: 'Review Status + Contributor Dashboard',
      unit: 'Show administrator decision',
      proponent: 'James Stephen O. Ramos',
      description: 'Show administrator decision',
      expectedResult: 'Current decision is visible',
      precondition: 'Reviewed submission exists',
      inputs: const <String, Object?>{
        'fixtureId': 'INT-024',
      },
    );

    // The adapter must execute real app code / observe real UI or backend state.
    final observed = await adapter!.execute(scenario);

      expect(
        observed['reviewDecisionDisplayed'],
        equals(true),
        reason: 'INT-024: reviewDecisionDisplayed does not match the real system result',
      );
      expect(
        observed['correctSubmissionLoaded'],
        equals(true),
        reason: 'INT-024: correctSubmissionLoaded does not match the real system result',
      );
  }, skip: adapter == null ? 'Not connected to real HeritageBot implementation' : false);
}
