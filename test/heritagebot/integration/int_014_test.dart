import 'package:flutter_test/flutter_test.dart';
import '../support/heritagebot_test_adapter.dart';

// INT-014 — RAG Pipeline + LLM Service / Generate grounded heritage narrative
// Proponent: AI Knowledge Base / System Team
// Test description: Generate grounded heritage narrative
// Expected result: Narrative reflects retrieved site evidence
// NOTE: Connect the adapter to actual HeritageBot code before recording a PASS.

void main() {
  final adapter = createHeritageBotTestAdapter();

  test('INT-014 - Generate grounded heritage narrative', () async {
    final scenario = HeritageBotScenario(
      id: 'INT-014',
      kind: 'integration',
      module: 'RAG Pipeline + LLM Service',
      unit: 'Generate grounded heritage narrative',
      proponent: 'AI Knowledge Base / System Team',
      description: 'Generate grounded heritage narrative',
      expectedResult: 'Narrative reflects retrieved site evidence',
      precondition: 'Valid retrieved context and AI connectivity',
      inputs: const <String, Object?>{
        'fixtureId': 'INT-014',
      },
    );

    // The adapter must execute real app code / observe real UI or backend state.
    final observed = await adapter!.execute(scenario);

      expect(
        observed['groundedNarrativeGenerated'],
        equals(true),
        reason: 'INT-014: groundedNarrativeGenerated does not match the real system result',
      );
      expect(
        observed['retrievedEvidenceUsed'],
        equals(true),
        reason: 'INT-014: retrievedEvidenceUsed does not match the real system result',
      );
  }, skip: adapter == null ? 'Not connected to real HeritageBot implementation' : false);
}
