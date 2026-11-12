import 'package:flutter_test/flutter_test.dart';
import '../support/heritagebot_test_adapter.dart';

// INT-018 — Heritage Site Details + Bookmarks / Save selected site
// Proponent: Reil Esdrelon
// Test description: Save selected site
// Expected result: Saved site appears in bookmarks
// NOTE: Connect the adapter to actual HeritageBot code before recording a PASS.

void main() {
  final adapter = createHeritageBotTestAdapter();

  test('INT-018 - Save selected site', () async {
    final scenario = HeritageBotScenario(
      id: 'INT-018',
      kind: 'integration',
      module: 'Heritage Site Details + Bookmarks',
      unit: 'Save selected site',
      proponent: 'Reil Esdrelon',
      description: 'Save selected site',
      expectedResult: 'Saved site appears in bookmarks',
      precondition: 'Authenticated tourist',
      inputs: const <String, Object?>{
        'fixtureId': 'INT-018',
      },
    );

    // The adapter must execute real app code / observe real UI or backend state.
    final observed = await adapter!.execute(scenario);

      expect(
        observed['bookmarkSaved'],
        equals(true),
        reason: 'INT-018: bookmarkSaved does not match the real system result',
      );
      expect(
        observed['bookmarkVisibleInList'],
        equals(true),
        reason: 'INT-018: bookmarkVisibleInList does not match the real system result',
      );
  }, skip: adapter == null ? 'Not connected to real HeritageBot implementation' : false);
}
