import 'package:flutter_test/flutter_test.dart';
import '../support/heritagebot_test_adapter.dart';

// INT-023 — Manage Submissions + Story Database / Edit pending story
// Proponent: James Stephen O. Ramos
// Test description: Edit pending story
// Expected result: Updated story is stored
// NOTE: Connect the adapter to actual HeritageBot code before recording a PASS.

void main() {
  final adapter = createHeritageBotTestAdapter();

  test('INT-023 - Edit pending story', () async {
    final scenario = HeritageBotScenario(
      id: 'INT-023',
      kind: 'integration',
      module: 'Manage Submissions + Story Database',
      unit: 'Edit pending story',
      proponent: 'James Stephen O. Ramos',
      description: 'Edit pending story',
      expectedResult: 'Updated story is stored',
      precondition: 'Contributor owns editable story',
      inputs: const <String, Object?>{
        'fixtureId': 'INT-023',
      },
    );

    // The adapter must execute real app code / observe real UI or backend state.
    final observed = await adapter!.execute(scenario);

      expect(
        observed['storyEdited'],
        equals(true),
        reason: 'INT-023: storyEdited does not match the real system result',
      );
      expect(
        observed['updatedStoryPersisted'],
        equals(true),
        reason: 'INT-023: updatedStoryPersisted does not match the real system result',
      );
  }, skip: adapter == null ? 'Not connected to real HeritageBot implementation' : false);
}
