// HERITAGEBOT - TEST SUPPORT: shared fixtures and UI helpers for
// CASE-031..CASE-050.
//
// Builds on heritagebot_test_harness.dart (unchanged). Nothing here renders
// a HeritageBot screen or produces a test result; it only
//   * seeds Firestore documents in exactly the shape HeritageBot's own
//     services write them (HeritagePlace.toMap, CommunitySubmission.toMap,
//     BookmarkService.addBookmark, AiNarrativeService.recordGeneratedNarrative),
//   * drives the REAL widgets from package:heritagebot/main.dart, and
//   * reads what those widgets display.

// ignore_for_file: depend_on_referenced_packages

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator_platform_interface/geolocator_platform_interface.dart';

import 'package:heritagebot/main.dart' as app;
import 'package:heritagebot/models/community_submission.dart';
import 'package:heritagebot/models/heritage_place.dart';
import 'package:heritagebot/models/user_profile.dart';

import 'heritagebot_test_harness.dart';

export 'heritagebot_test_harness.dart';

// ---------------------------------------------------------------------------
// HERITAGE SITES
// ---------------------------------------------------------------------------

/// Administrator-registered "Magellan's Cross" record - identical to the
/// fixture used by CASE-022. It is NOT one of the four sites bundled in
/// lib/models/heritage_place.dart; it exists only once an Administrator
/// registers it in the Firestore `heritage_sites` collection.
const HeritagePlace kMagellansCross = HeritagePlace(
  id: 'magellans_cross',
  name: "Magellan's Cross",
  location: 'Magallanes Street, Cebu City',
  lat: 10.29353,
  lng: 123.90187,
  videoTitle: "Magellan's Cross Video",
  wikipediaTitle: "Magellan's Cross",
  detectionRadiusMeters: 20000,
  historicalFacts:
      "Magellan's Cross is a Christian cross planted by the expedition of "
      'Ferdinand Magellan upon arriving in Cebu in 1521. It is housed in a '
      'chapel beside the Basilica Minore del Santo Niño.',
);

/// One of the four sites bundled with HeritageBot.
HeritagePlace bundledSite(String id) =>
    defaultHeritagePlaces.singleWhere((site) => site.id == id);

/// Seeds `heritage_sites/{id}` for every site, as the Administrator's
/// HeritageSiteService.createSite / seedDefaultSites would.
void seedRegisteredSites(
  HeritageBotTestBackend backend,
  Iterable<HeritagePlace> sites,
) {
  for (final site in sites) {
    backend.firestore.seedDocument('heritage_sites/${site.id}', <String, dynamic>{
      ...site.toMap(),
      'createdAtMillis': 1,
      'updatedAtMillis': 1,
    });
  }
}

// ---------------------------------------------------------------------------
// ACCOUNTS
// ---------------------------------------------------------------------------

/// Seeds users/{uid} for a Community Contributor.
void seedContributor(HeritageBotTestBackend backend, FakeAuthAccount account) {
  backend.seedProfile(
    uid: account.uid,
    email: account.email,
    fullName: account.displayName ?? 'Test Contributor',
    role: UserRoles.communityContributor,
  );
}

// ---------------------------------------------------------------------------
// COMMUNITY STORIES
// ---------------------------------------------------------------------------

/// A community_submissions document in the exact shape that
/// CommunitySubmissionService.submitStory / reviewSubmission write.
CommunitySubmission storyFixture({
  required String id,
  required String title,
  required String status,
  required HeritagePlace site,
  String contributorId = 'fixture-contributor-uid',
  String contributorName = 'Maria Santos',
  String? story,
  int createdAtMillis = 1767225600000, // 2026-01-01
  int? updatedAtMillis,
}) {
  return CommunitySubmission(
    id: id,
    contributorId: contributorId,
    contributorName: contributorName,
    contributorEmail: 'contributor@heritagebot.test',
    heritagePlaceId: site.id,
    heritagePlaceName: site.name,
    title: title,
    story: story ??
        'My grandmother often brought us to ${site.name} after Sunday mass. '
            'She told us how the old people of Cebu gathered here, and why '
            'the place still matters to the families who live nearby.',
    status: status,
    adminFeedback: status == CommunitySubmissionStatus.approved
        ? 'Approved by Administrator.'
        : '',
    imageUrls: const <String>[],
    videoUrls: const <String>[],
    createdAtMillis: createdAtMillis,
    updatedAtMillis: updatedAtMillis ?? createdAtMillis + 86400000,
  );
}

void seedStory(HeritageBotTestBackend backend, CommunitySubmission story) {
  backend.firestore
      .seedDocument('community_submissions/${story.id}', story.toMap());
}

/// All community_submissions documents currently stored.
Map<String, Map<String, dynamic>> storedSubmissions(
  HeritageBotTestBackend backend,
) =>
    Map<String, Map<String, dynamic>>.fromEntries(
      backend.firestore.documents.entries
          .where((e) => e.key.startsWith('community_submissions/')),
    );

// ---------------------------------------------------------------------------
// GPS
// ---------------------------------------------------------------------------

/// Location on, permission granted, device reports [lat]/[lng].
void placeTouristAt(
  HeritageBotTestBackend backend, {
  required double lat,
  required double lng,
  double accuracy = 5,
}) {
  backend.geolocator
    ..serviceEnabled = true
    ..permission = LocationPermission.whileInUse
    ..currentFix = fakeGpsFix(latitude: lat, longitude: lng, accuracy: accuracy);
}

// ---------------------------------------------------------------------------
// UI HELPERS
// ---------------------------------------------------------------------------

/// Plain text of every Text / RichText currently built under [scope].
List<String> textsUnder(WidgetTester tester, Finder scope) {
  final texts = <String>[];
  for (final widget in tester.widgetList(
    find.descendant(
      of: scope,
      matching: find.byWidgetPredicate((w) => w is Text || w is RichText),
      skipOffstage: false,
    ),
  )) {
    if (widget is Text) {
      final value = widget.data ?? widget.textSpan?.toPlainText() ?? '';
      if (value.isNotEmpty) texts.add(value);
    } else if (widget is RichText) {
      final value = widget.text.toPlainText();
      if (value.isNotEmpty) texts.add(value);
    }
  }
  return texts;
}

/// True when any text under [scope] matches [pattern].
bool anyTextMatches(WidgetTester tester, Finder scope, RegExp pattern) =>
    textsUnder(tester, scope).any(pattern.hasMatch);

/// Opens the real Geolocation tab of MainShell and waits for the screen.
Future<void> openGeolocationTab(WidgetTester tester) async {
  await tapNavDestination(tester, en('geolocation'));
  await pumpUntilFound(tester, find.byType(app.GeolocationScreen));
}

/// Waits until the location-triggered narrative bottom sheet has finished
/// loading its story (success OR failure card).
Future<void> waitForNarrativePanel(WidgetTester tester) async {
  await pumpUntilFound(tester, find.byType(app.NarrativeAutoPlaybackPanel));
  for (var i = 0; i < 100; i++) {
    await tester.pump(const Duration(milliseconds: 50));
    final loading = find.descendant(
      of: find.byType(app.NarrativeAutoPlaybackPanel),
      matching: find.text(en('generatingStory')),
    );
    if (loading.evaluate().isEmpty) break;
  }
  await pumpFor(tester, const Duration(milliseconds: 300));
}

/// The real InfoCard rendered by NarrativeAutoPlaybackPanel (null if none).
app.InfoCard? narrativeCard(WidgetTester tester) {
  final cards = tester.widgetList<app.InfoCard>(find.descendant(
    of: find.byType(app.NarrativeAutoPlaybackPanel),
    matching: find.byType(app.InfoCard),
  ));
  return cards.isEmpty ? null : cards.first;
}

/// Home -> "Explore Heritage by Location" -> type [query] -> tap the
/// matching registered site [siteName] -> HeritageSiteDetailScreen.
Future<void> openSiteDetailFromSearch(
  WidgetTester tester, {
  required String query,
  required String siteName,
}) async {
  await tapVisible(tester, find.text('Explore Heritage by Location'));
  await pumpUntilFound(tester, find.byType(app.HeritageSiteSearchScreen));
  await tester.enterText(fieldsOf(app.HeritageSiteSearchScreen).first, query);
  await tester.pump();
  await tapVisible(
    tester,
    find.descendant(of: find.byType(ListTile), matching: find.text(siteName)),
  );
  await pumpUntilFound(tester, find.byType(app.HeritageSiteDetailScreen));
  await pumpFor(tester, const Duration(milliseconds: 300));
}

/// System "Back" on the route that shows [screen] (pops it like the
/// Android back button / AppBar back arrow).
Future<void> goBackFrom(WidgetTester tester, Type screen) async {
  final screenFinder = find.byType(screen);
  expect(screenFinder, findsOneWidget);
  Navigator.of(tester.element(screenFinder)).pop();
  await tester.pump();
  await pumpUntilGone(tester, screenFinder);
  await pumpFor(tester, const Duration(milliseconds: 300));
}

/// Profile tab -> "View Bookmarked Sites" -> BookmarkedSitesScreen (loaded).
Future<void> openBookmarkedSitesFromProfile(WidgetTester tester) async {
  await tapNavDestination(tester, en('profile'));
  await pumpUntilFound(tester, find.byType(app.ProfileScreen));
  final entry = find.text('View Bookmarked Sites');
  await scrollUntilBuilt(tester, entry, screen: app.ProfileScreen);
  await tapVisible(tester, entry);
  await pumpUntilFound(tester, find.byType(app.BookmarkedSitesScreen));
  await pumpUntilFound(tester, find.text('Saved Heritage Sites'));
}

/// Site names listed on the real BookmarkedSitesScreen.
List<String> bookmarkedSiteNames(WidgetTester tester) => tester
    .widgetList<ListTile>(find.descendant(
      of: find.byType(app.BookmarkedSitesScreen),
      matching: find.byType(ListTile),
    ))
    .map((tile) => (tile.title is Text) ? (tile.title as Text).data ?? '' : '')
    .where((name) => name.isNotEmpty)
    .toList();

/// Opens the real Stories tab and waits for the list to finish loading.
Future<void> openStoriesTab(WidgetTester tester) async {
  await tapNavDestination(tester, 'Stories');
  await pumpUntilFound(tester, find.text('Approved Local Stories'));
  await pumpFor(tester, const Duration(milliseconds: 300));
}

/// Titles of the story cards currently listed on CommunityStoriesScreen
/// (each card shows the "verified" icon next to its title).
List<String> listedStoryTitles(WidgetTester tester) {
  final screen = find.byType(app.CommunityStoriesScreen);
  final titles = <String>[];
  for (final card in find
      .descendant(of: screen, matching: find.byType(Card), skipOffstage: false)
      .evaluate()) {
    final cardFinder = find.byElementPredicate((e) => e == card);
    final hasVerified = find
        .descendant(
            of: cardFinder,
            matching: find.byIcon(Icons.verified_rounded),
            skipOffstage: false)
        .evaluate()
        .isNotEmpty;
    if (!hasVerified) continue;
    // Title = first Text widget in the card's header row (Icons render as
    // RichText, not Text, so they are skipped).
    final row = find.descendant(
        of: cardFinder, matching: find.byType(Row), skipOffstage: false);
    final rowTexts = tester
        .widgetList<Text>(find.descendant(
            of: row.first, matching: find.byType(Text), skipOffstage: false))
        .map((t) => t.data ?? '')
        .where((t) => t.isNotEmpty)
        .toList();
    if (rowTexts.isNotEmpty) titles.add(rowTexts.first);
  }
  return titles;
}
