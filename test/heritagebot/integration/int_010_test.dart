import 'package:flutter_test/flutter_test.dart';
import '../support/heritagebot_test_adapter.dart';

// INT-010 — Interactive Map + Heritage Site Details / Open selected site marker
// Proponent: Reil Esdrelon
// Test description: Open selected site marker
// Expected result: Correct heritage record opens
// NOTE: Connect the adapter to actual HeritageBot code before recording a PASS.

void main() {
  final adapter = createHeritageBotTestAdapter();

  test('INT-010 - Open selected site marker', () async {
    final scenario = HeritageBotScenario(
      id: 'INT-010',
      kind: 'integration',
      module: 'Interactive Map + Heritage Site Details',
      unit: 'Open selected site marker',
      proponent: 'Reil Esdrelon',
      description: 'Open selected site marker',
      expectedResult: 'Correct heritage record opens',
      precondition: 'Site marker exists',
      inputs: const <String, Object?>{
        'fixtureId': 'INT-010',
      },
    );

    // The adapter must execute real app code / observe real UI or backend state.
    final observed = await adapter!.execute(scenario);

      expect(
        observed['correctMarkerSelected'],
        equals(true),
        reason: 'INT-010: correctMarkerSelected does not match the real system result',
      );
      expect(
        observed['matchingSiteDetailsOpened'],
        equals(true),
        reason: 'INT-010: matchingSiteDetailsOpened does not match the real system result',
      );
  }, skip: adapter == null ? 'Not connected to real HeritageBot implementation' : false);
}
