import 'package:flutter_test/flutter_test.dart';
import '../support/heritagebot_test_adapter.dart';

// INT-031 — Heritage Media Management + Tourist Media Viewer / Publish media for heritage site
// Proponent: Shawn Guillmar C. Morales
// Test description: Publish media for heritage site
// Expected result: Correct published media appears
// NOTE: Connect the adapter to actual HeritageBot code before recording a PASS.

void main() {
  final adapter = createHeritageBotTestAdapter();

  test('INT-031 - Publish media for heritage site', () async {
    final scenario = HeritageBotScenario(
      id: 'INT-031',
      kind: 'integration',
      module: 'Heritage Media Management + Tourist Media Viewer',
      unit: 'Publish media for heritage site',
      proponent: 'Shawn Guillmar C. Morales',
      description: 'Publish media for heritage site',
      expectedResult: 'Correct published media appears',
      precondition: 'Media upload completed',
      inputs: const <String, Object?>{
        'fixtureId': 'INT-031',
      },
    );

    // The adapter must execute real app code / observe real UI or backend state.
    final observed = await adapter!.execute(scenario);

      expect(
        observed['publishedMediaSaved'],
        equals(true),
        reason: 'INT-031: publishedMediaSaved does not match the real system result',
      );
      expect(
        observed['touristMediaVisible'],
        equals(true),
        reason: 'INT-031: touristMediaVisible does not match the real system result',
      );
  }, skip: adapter == null ? 'Not connected to real HeritageBot implementation' : false);
}
