import 'package:flutter_test/flutter_test.dart';
import '../support/heritagebot_test_adapter.dart';

// INT-012 — Historical Data + Vector Database / Prepare and index historical chunks
// Proponent: AI Knowledge Base / System Team
// Test description: Prepare and index historical chunks
// Expected result: Embeddings are linked to correct source and site
// NOTE: Connect the adapter to actual HeritageBot code before recording a PASS.

void main() {
  final adapter = createHeritageBotTestAdapter();

  test('INT-012 - Prepare and index historical chunks', () async {
    final scenario = HeritageBotScenario(
      id: 'INT-012',
      kind: 'integration',
      module: 'Historical Data + Vector Database',
      unit: 'Prepare and index historical chunks',
      proponent: 'AI Knowledge Base / System Team',
      description: 'Prepare and index historical chunks',
      expectedResult: 'Embeddings are linked to correct source and site',
      precondition: 'Verified source data exists',
      inputs: const <String, Object?>{
        'fixtureId': 'INT-012',
      },
    );

    // The adapter must execute real app code / observe real UI or backend state.
    final observed = await adapter!.execute(scenario);

      expect(
        observed['historicalChunksIndexed'],
        equals(true),
        reason: 'INT-012: historicalChunksIndexed does not match the real system result',
      );
      expect(
        observed['embeddingSiteLinksCorrect'],
        equals(true),
        reason: 'INT-012: embeddingSiteLinksCorrect does not match the real system result',
      );
  }, skip: adapter == null ? 'Not connected to real HeritageBot implementation' : false);
}
