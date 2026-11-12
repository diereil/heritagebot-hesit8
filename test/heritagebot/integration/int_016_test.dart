import 'package:flutter_test/flutter_test.dart';
import '../support/heritagebot_test_adapter.dart';

// INT-016 — AI Narrative Generator + Audio Narration / Play generated narrative
// Proponent: Reil Esdrelon
// Test description: Play generated narrative
// Expected result: Selected narrative is narrated
// NOTE: Connect the adapter to actual HeritageBot code before recording a PASS.

void main() {
  final adapter = createHeritageBotTestAdapter();

  test('INT-016 - Play generated narrative', () async {
    final scenario = HeritageBotScenario(
      id: 'INT-016',
      kind: 'integration',
      module: 'AI Narrative Generator + Audio Narration',
      unit: 'Play generated narrative',
      proponent: 'Reil Esdrelon',
      description: 'Play generated narrative',
      expectedResult: 'Selected narrative is narrated',
      precondition: 'Narrative and audio service available',
      inputs: const <String, Object?>{
        'fixtureId': 'INT-016',
      },
    );

    // The adapter must execute real app code / observe real UI or backend state.
    final observed = await adapter!.execute(scenario);

      expect(
        observed['audioStarted'],
        equals(true),
        reason: 'INT-016: audioStarted does not match the real system result',
      );
      expect(
        observed['correctNarrativeSpoken'],
        equals(true),
        reason: 'INT-016: correctNarrativeSpoken does not match the real system result',
      );
  }, skip: adapter == null ? 'Not connected to real HeritageBot implementation' : false);
}
