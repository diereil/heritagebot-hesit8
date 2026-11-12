// HERITAGEBOT - TEST CASE 061
// Proponent: James Stephen O. Ramos
// Module: Community Contributor Management
// Unit: Track Submission Status
// Description: View pending submission.
// Expected: Display pending status.
//
// TEST TYPE: Flutter widget test (host VM, no device / live Firebase).
//
// REAL CODE UNDER TEST (lib/, unmodified)
//   ContributorDashboardScreen -> getMySubmissions -> submission card status
//   chip (CommunitySubmissionStatus.label) + status icon.
//
// FIXTURE (fixtureId = CASE-061): one story submitted by the signed-in
// contributor and not yet reviewed (status = pending).
//
// OBSERVATION: submissionStatus is the status value that corresponds to the
// label actually DISPLAYED on the card (mapped back with the app's own
// CommunitySubmissionStatus.label), not the value read from Firestore.
//
// MOCKED: Firebase platform layer only (in-memory Firestore).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:heritagebot/main.dart' as app;
import 'package:heritagebot/models/community_submission.dart';

import '../support/contributor_flow.dart';
import '../support/heritagebot_fixtures.dart';

const FakeAuthAccount kContributor = FakeAuthAccount(
  uid: 'case061-contributor-uid',
  email: 'case061.contributor@heritagebot.test',
  password: 'Case061Pass!',
  displayName: 'James Contributor',
);

final CommunitySubmission kPending = storyFixture(
  id: 'case061-pending',
  title: 'Waiting for the Fiesta at the Monument',
  status: CommunitySubmissionStatus.pending,
  site: bundledSite('cebu_heritage_monument'),
  contributorId: kContributor.uid,
  contributorName: 'James Contributor',
);

late HeritageBotTestBackend backend;

void main() {
  setUpAll(() async {
    backend = await HeritageBotTestBackend.install(accounts: [kContributor]);
  });

  setUp(() async {
    await backend.reset();
    seedContributor(backend, kContributor);
    seedStory(backend, kPending);
  });

  testWidgets('CASE-061 - View pending submission', (
    WidgetTester tester,
  ) async {
    usePhoneSurface(tester);

    await signInBeforeLaunch(kContributor);
    await openContributorDashboard(tester);

    // ---- Observations ---------------------------------------------------
    final cards = await collectDashboardCards(tester);
    final card = cards[kPending.title];
    final titleFinder = find.descendant(
      of: find.byType(app.ContributorDashboardScreen),
      matching: find.text(kPending.title),
    );
    final cardFinder = find
        .ancestor(of: titleFinder, matching: find.byType(Card))
        .first;
    final pendingIcon = find
        .descendant(
          of: cardFinder,
          matching: find.byIcon(Icons.schedule_rounded),
        )
        .evaluate()
        .isNotEmpty;

    final observed = <String, Object?>{
      'submissionStatus': card == null
          ? null
          : statusForLabel(card.statusLabel),
      'statusVisible':
          card != null &&
          card.statusLabel.isNotEmpty &&
          tester
              .getRect(
                find.descendant(
                  of: cardFinder,
                  matching: find.text(card.statusLabel),
                ),
              )
              .overlaps(
                tester.getRect(find.byType(app.ContributorDashboardScreen)),
              ),
    };
    printOnFailure(
      'CASE-061 observed: $observed\ncard=$card '
      'pendingIcon=$pendingIcon',
    );

    // ---- Expected result (unchanged from the original CASE-061) ---------
    expect(
      observed['submissionStatus'],
      equals('pending'),
      reason:
          'CASE-061: submissionStatus does not match the real system result',
    );
    expect(
      observed['statusVisible'],
      equals(true),
      reason: 'CASE-061: statusVisible does not match the real system result',
    );
    // Supporting evidence: the pending (clock) icon is shown on the card.
    expect(pendingIcon, isTrue);

    await unmountApp(tester);
  });
}
