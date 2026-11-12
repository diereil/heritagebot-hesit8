import 'package:flutter_test/flutter_test.dart';
import '../support/heritagebot_test_adapter.dart';

// INT-036 — Knowledge Base Updates + Vector Retrieval / Refresh embeddings after source edit
// Proponent: AI Knowledge Base / System Team
// Test description: Refresh embeddings after source edit
// Expected result: Retrieval reflects current verified content
// NOTE: Connect the adapter to actual HeritageBot code before recording a PASS.

void main() {
  final adapter = createHeritageBotTestAdapter();

  test('INT-036 - Refresh embeddings after source edit', () async {
    final scenario = HeritageBotScenario(
      id: 'INT-036',
      kind: 'integration',
      module: 'Knowledge Base Updates + Vector Retrieval',
      unit: 'Refresh embeddings after source edit',
      proponent: 'AI Knowledge Base / System Team',
      description: 'Refresh embeddings after source edit',
      expectedResult: 'Retrieval reflects current verified content',
      precondition: 'Authorized historical edit completed',
      inputs: const <String, Object?>{
        'fixtureId': 'INT-036',
      },
    );

    // The adapter must execute real app code / observe real UI or backend state.
    final observed = await adapter!.execute(scenario);

      expect(
        observed['indexRefreshed'],
        equals(true),
        reason: 'INT-036: indexRefreshed does not match the real system result',
      );
      expect(
        observed['updatedContentRetrieved'],
        equals(true),
        reason: 'INT-036: updatedContentRetrieved does not match the real system result',
      );
  }, skip: adapter == null ? 'Not connected to real HeritageBot implementation' : false);
}
