import 'package:flutter_test/flutter_test.dart';
import '../support/heritagebot_test_adapter.dart';

// INT-025 — Review Feedback + Contributor Dashboard / Read reviewer comments
// Proponent: James Stephen O. Ramos
// Test description: Read reviewer comments
// Expected result: Correct feedback appears
// NOTE: Connect the adapter to actual HeritageBot code before recording a PASS.

void main() {
  final adapter = createHeritageBotTestAdapter();

  test('INT-025 - Read reviewer comments', () async {
    final scenario = HeritageBotScenario(
      id: 'INT-025',
      kind: 'integration',
      module: 'Review Feedback + Contributor Dashboard',
      unit: 'Read reviewer comments',
      proponent: 'James Stephen O. Ramos',
      description: 'Read reviewer comments',
      expectedResult: 'Correct feedback appears',
      precondition: 'Feedback exists for own submission',
      inputs: const <String, Object?>{
        'fixtureId': 'INT-025',
      },
    );

    // The adapter must execute real app code / observe real UI or backend state.
    final observed = await adapter!.execute(scenario);

      expect(
        observed['feedbackDisplayed'],
        equals(true),
        reason: 'INT-025: feedbackDisplayed does not match the real system result',
      );
      expect(
        observed['feedbackMatchesReview'],
        equals(true),
        reason: 'INT-025: feedbackMatchesReview does not match the real system result',
      );
  }, skip: adapter == null ? 'Not connected to real HeritageBot implementation' : false);
}
