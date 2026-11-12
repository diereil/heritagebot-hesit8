import 'package:flutter_test/flutter_test.dart';
import '../support/heritagebot_test_adapter.dart';

// INT-017 — Heritage Site Details + Media Storage / Load associated heritage video
// Proponent: Reil Esdrelon
// Test description: Load associated heritage video
// Expected result: Correct media loads
// NOTE: Connect the adapter to actual HeritageBot code before recording a PASS.

void main() {
  final adapter = createHeritageBotTestAdapter();

  test('INT-017 - Load associated heritage video', () async {
    final scenario = HeritageBotScenario(
      id: 'INT-017',
      kind: 'integration',
      module: 'Heritage Site Details + Media Storage',
      unit: 'Load associated heritage video',
      proponent: 'Reil Esdrelon',
      description: 'Load associated heritage video',
      expectedResult: 'Correct media loads',
      precondition: 'Site has published media',
      inputs: const <String, Object?>{
        'fixtureId': 'INT-017',
      },
    );

    // The adapter must execute real app code / observe real UI or backend state.
    final observed = await adapter!.execute(scenario);

      expect(
        observed['mediaLoaded'],
        equals(true),
        reason: 'INT-017: mediaLoaded does not match the real system result',
      );
      expect(
        observed['correctHeritageMediaShown'],
        equals(true),
        reason: 'INT-017: correctHeritageMediaShown does not match the real system result',
      );
  }, skip: adapter == null ? 'Not connected to real HeritageBot implementation' : false);
}
