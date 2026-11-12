import 'package:flutter_test/flutter_test.dart';
import '../support/heritagebot_test_adapter.dart';

// INT-022 — Story Submission + Media Storage / Upload supporting photo or video
// Proponent: James Stephen O. Ramos
// Test description: Upload supporting photo or video
// Expected result: Media attaches to correct submission
// NOTE: Connect the adapter to actual HeritageBot code before recording a PASS.

void main() {
  final adapter = createHeritageBotTestAdapter();

  test('INT-022 - Upload supporting photo or video', () async {
    final scenario = HeritageBotScenario(
      id: 'INT-022',
      kind: 'integration',
      module: 'Story Submission + Media Storage',
      unit: 'Upload supporting photo or video',
      proponent: 'James Stephen O. Ramos',
      description: 'Upload supporting photo or video',
      expectedResult: 'Media attaches to correct submission',
      precondition: 'Valid supported media selected',
      inputs: const <String, Object?>{
        'fixtureId': 'INT-022',
      },
    );

    // The adapter must execute real app code / observe real UI or backend state.
    final observed = await adapter!.execute(scenario);

      expect(
        observed['mediaUploaded'],
        equals(true),
        reason: 'INT-022: mediaUploaded does not match the real system result',
      );
      expect(
        observed['correctSubmissionAssociation'],
        equals(true),
        reason: 'INT-022: correctSubmissionAssociation does not match the real system result',
      );
  }, skip: adapter == null ? 'Not connected to real HeritageBot implementation' : false);
}
