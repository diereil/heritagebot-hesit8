import 'package:flutter_test/flutter_test.dart';
import '../support/heritagebot_test_adapter.dart';

// INT-011 — Heritage Site Details + RAG Retrieval / Request historical narrative
// Proponent: Reil Esdrelon
// Test description: Request historical narrative
// Expected result: Relevant site-specific context is retrieved
// NOTE: Connect the adapter to actual HeritageBot code before recording a PASS.

void main() {
  final adapter = createHeritageBotTestAdapter();

  test('INT-011 - Request historical narrative', () async {
    final scenario = HeritageBotScenario(
      id: 'INT-011',
      kind: 'integration',
      module: 'Heritage Site Details + RAG Retrieval',
      unit: 'Request historical narrative',
      proponent: 'Reil Esdrelon',
      description: 'Request historical narrative',
      expectedResult: 'Relevant site-specific context is retrieved',
      precondition: 'Verified indexed site sources exist',
      inputs: const <String, Object?>{
        'fixtureId': 'INT-011',
      },
    );

    // The adapter must execute real app code / observe real UI or backend state.
    final observed = await adapter!.execute(scenario);

      expect(
        observed['narrativeRequestCreated'],
        equals(true),
        reason: 'INT-011: narrativeRequestCreated does not match the real system result',
      );
      expect(
        observed['matchingSiteChunksRetrieved'],
        equals(true),
        reason: 'INT-011: matchingSiteChunksRetrieved does not match the real system result',
      );
  }, skip: adapter == null ? 'Not connected to real HeritageBot implementation' : false);
}
