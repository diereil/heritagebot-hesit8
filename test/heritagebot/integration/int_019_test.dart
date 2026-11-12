import 'package:flutter_test/flutter_test.dart';
import '../support/heritagebot_test_adapter.dart';

// INT-019 — Bookmarks + Heritage Site Details / Reopen saved site
// Proponent: Reil Esdrelon
// Test description: Reopen saved site
// Expected result: Correct saved site opens
// NOTE: Connect the adapter to actual HeritageBot code before recording a PASS.

void main() {
  final adapter = createHeritageBotTestAdapter();

  test('INT-019 - Reopen saved site', () async {
    final scenario = HeritageBotScenario(
      id: 'INT-019',
      kind: 'integration',
      module: 'Bookmarks + Heritage Site Details',
      unit: 'Reopen saved site',
      proponent: 'Reil Esdrelon',
      description: 'Reopen saved site',
      expectedResult: 'Correct saved site opens',
      precondition: 'Saved bookmark exists',
      inputs: const <String, Object?>{
        'fixtureId': 'INT-019',
      },
    );

    // The adapter must execute real app code / observe real UI or backend state.
    final observed = await adapter!.execute(scenario);

      expect(
        observed['bookmarkOpened'],
        equals(true),
        reason: 'INT-019: bookmarkOpened does not match the real system result',
      );
      expect(
        observed['correctSiteDetailsLoaded'],
        equals(true),
        reason: 'INT-019: correctSiteDetailsLoaded does not match the real system result',
      );
  }, skip: adapter == null ? 'Not connected to real HeritageBot implementation' : false);
}
