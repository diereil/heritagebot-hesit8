import 'package:flutter_test/flutter_test.dart';
import '../support/heritagebot_test_adapter.dart';

// INT-027 — Review Queue + Public Community Stories / Reject community story
// Proponent: Shawn Guillmar C. Morales
// Test description: Reject community story
// Expected result: Rejected story stays hidden publicly
// NOTE: Connect the adapter to actual HeritageBot code before recording a PASS.

void main() {
  final adapter = createHeritageBotTestAdapter();

  test('INT-027 - Reject community story', () async {
    final scenario = HeritageBotScenario(
      id: 'INT-027',
      kind: 'integration',
      module: 'Review Queue + Public Community Stories',
      unit: 'Reject community story',
      proponent: 'Shawn Guillmar C. Morales',
      description: 'Reject community story',
      expectedResult: 'Rejected story stays hidden publicly',
      precondition: 'Pending story exists',
      inputs: const <String, Object?>{
        'fixtureId': 'INT-027',
      },
    );

    // The adapter must execute real app code / observe real UI or backend state.
    final observed = await adapter!.execute(scenario);

      expect(
        observed['storyRejected'],
        equals(true),
        reason: 'INT-027: storyRejected does not match the real system result',
      );
      expect(
        observed['storyPubliclyVisible'],
        equals(false),
        reason: 'INT-027: storyPubliclyVisible does not match the real system result',
      );
  }, skip: adapter == null ? 'Not connected to real HeritageBot implementation' : false);
}
