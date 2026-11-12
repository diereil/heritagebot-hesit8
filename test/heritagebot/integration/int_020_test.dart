import 'package:flutter_test/flutter_test.dart';
import '../support/heritagebot_test_adapter.dart';

// INT-020 — Community Stories + Moderation Records / Open published story
// Proponent: Reil Esdrelon
// Test description: Open published story
// Expected result: Only approved story is displayed
// NOTE: Connect the adapter to actual HeritageBot code before recording a PASS.

void main() {
  final adapter = createHeritageBotTestAdapter();

  test('INT-020 - Open published story', () async {
    final scenario = HeritageBotScenario(
      id: 'INT-020',
      kind: 'integration',
      module: 'Community Stories + Moderation Records',
      unit: 'Open published story',
      proponent: 'Reil Esdrelon',
      description: 'Open published story',
      expectedResult: 'Only approved story is displayed',
      precondition: 'Approved story exists',
      inputs: const <String, Object?>{
        'fixtureId': 'INT-020',
      },
    );

    // The adapter must execute real app code / observe real UI or backend state.
    final observed = await adapter!.execute(scenario);

      expect(
        observed['approvedStoryVisible'],
        equals(true),
        reason: 'INT-020: approvedStoryVisible does not match the real system result',
      );
      expect(
        observed['unapprovedStoryHidden'],
        equals(true),
        reason: 'INT-020: unapprovedStoryHidden does not match the real system result',
      );
  }, skip: adapter == null ? 'Not connected to real HeritageBot implementation' : false);
}
