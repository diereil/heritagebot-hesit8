import 'package:flutter_test/flutter_test.dart';
import '../support/heritagebot_test_adapter.dart';

// INT-026 — Review Queue + Public Community Stories / Approve community story
// Proponent: Shawn Guillmar C. Morales
// Test description: Approve community story
// Expected result: Approved story becomes publicly visible
// NOTE: Connect the adapter to actual HeritageBot code before recording a PASS.

void main() {
  final adapter = createHeritageBotTestAdapter();

  test('INT-026 - Approve community story', () async {
    final scenario = HeritageBotScenario(
      id: 'INT-026',
      kind: 'integration',
      module: 'Review Queue + Public Community Stories',
      unit: 'Approve community story',
      proponent: 'Shawn Guillmar C. Morales',
      description: 'Approve community story',
      expectedResult: 'Approved story becomes publicly visible',
      precondition: 'Pending valid story exists',
      inputs: const <String, Object?>{
        'fixtureId': 'INT-026',
      },
    );

    // The adapter must execute real app code / observe real UI or backend state.
    final observed = await adapter!.execute(scenario);

      expect(
        observed['storyApproved'],
        equals(true),
        reason: 'INT-026: storyApproved does not match the real system result',
      );
      expect(
        observed['storyPubliclyVisible'],
        equals(true),
        reason: 'INT-026: storyPubliclyVisible does not match the real system result',
      );
  }, skip: adapter == null ? 'Not connected to real HeritageBot implementation' : false);
}
