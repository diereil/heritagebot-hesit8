import 'package:flutter_test/flutter_test.dart';
import '../support/heritagebot_test_adapter.dart';

// INT-039 — Network Connection + Narrative Viewer / Handle AI service interruption
// Proponent: AI Knowledge Base / System Team
// Test description: Handle AI service interruption
// Expected result: Error shown without fabricated narrative
// NOTE: Connect the adapter to actual HeritageBot code before recording a PASS.

void main() {
  final adapter = createHeritageBotTestAdapter();

  test('INT-039 - Handle AI service interruption', () async {
    final scenario = HeritageBotScenario(
      id: 'INT-039',
      kind: 'integration',
      module: 'Network Connection + Narrative Viewer',
      unit: 'Handle AI service interruption',
      proponent: 'AI Knowledge Base / System Team',
      description: 'Handle AI service interruption',
      expectedResult: 'Error shown without fabricated narrative',
      precondition: 'AI service unavailable',
      inputs: const <String, Object?>{
        'fixtureId': 'INT-039',
      },
    );

    // The adapter must execute real app code / observe real UI or backend state.
    final observed = await adapter!.execute(scenario);

      expect(
        observed['aiErrorDisplayed'],
        equals(true),
        reason: 'INT-039: aiErrorDisplayed does not match the real system result',
      );
      expect(
        observed['fabricatedNarrativeDisplayed'],
        equals(false),
        reason: 'INT-039: fabricatedNarrativeDisplayed does not match the real system result',
      );
  }, skip: adapter == null ? 'Not connected to real HeritageBot implementation' : false);
}
