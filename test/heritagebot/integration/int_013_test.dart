import 'package:flutter_test/flutter_test.dart';
import '../support/heritagebot_test_adapter.dart';

// INT-013 — Vector Database + RAG Pipeline / Retrieve relevant historical chunks
// Proponent: AI Knowledge Base / System Team
// Test description: Retrieve relevant historical chunks
// Expected result: RAG receives relevant retrieved context
// NOTE: Connect the adapter to actual HeritageBot code before recording a PASS.

void main() {
  final adapter = createHeritageBotTestAdapter();

  test('INT-013 - Retrieve relevant historical chunks', () async {
    final scenario = HeritageBotScenario(
      id: 'INT-013',
      kind: 'integration',
      module: 'Vector Database + RAG Pipeline',
      unit: 'Retrieve relevant historical chunks',
      proponent: 'AI Knowledge Base / System Team',
      description: 'Retrieve relevant historical chunks',
      expectedResult: 'RAG receives relevant retrieved context',
      precondition: 'Indexed matching records exist',
      inputs: const <String, Object?>{
        'fixtureId': 'INT-013',
      },
    );

    // The adapter must execute real app code / observe real UI or backend state.
    final observed = await adapter!.execute(scenario);

      expect(
        observed['vectorQueryComplete'],
        equals(true),
        reason: 'INT-013: vectorQueryComplete does not match the real system result',
      );
      expect(
        observed['retrievedContextUsedByRag'],
        equals(true),
        reason: 'INT-013: retrievedContextUsedByRag does not match the real system result',
      );
  }, skip: adapter == null ? 'Not connected to real HeritageBot implementation' : false);
}
