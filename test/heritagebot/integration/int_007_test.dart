import 'package:flutter_test/flutter_test.dart';
import '../support/heritagebot_test_adapter.dart';

// INT-007 — Tourist Home + Heritage Site Records / Search and select a site
// Proponent: Reil Esdrelon
// Test description: Search and select a site
// Expected result: Selected site information opens
// NOTE: Connect the adapter to actual HeritageBot code before recording a PASS.

void main() {
  final adapter = createHeritageBotTestAdapter();

  test('INT-007 - Search and select a site', () async {
    final scenario = HeritageBotScenario(
      id: 'INT-007',
      kind: 'integration',
      module: 'Tourist Home + Heritage Site Records',
      unit: 'Search and select a site',
      proponent: 'Reil Esdrelon',
      description: 'Search and select a site',
      expectedResult: 'Selected site information opens',
      precondition: 'Published site exists',
      inputs: const <String, Object?>{
        'fixtureId': 'INT-007',
      },
    );

    // The adapter must execute real app code / observe real UI or backend state.
    final observed = await adapter!.execute(scenario);

      expect(
        observed['siteSearchMatched'],
        equals(true),
        reason: 'INT-007: siteSearchMatched does not match the real system result',
      );
      expect(
        observed['correctHeritageDetailsOpened'],
        equals(true),
        reason: 'INT-007: correctHeritageDetailsOpened does not match the real system result',
      );
  }, skip: adapter == null ? 'Not connected to real HeritageBot implementation' : false);
}
