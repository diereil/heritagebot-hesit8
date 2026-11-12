// HERITAGEBOT - TEST SUPPORT: drives and reads the REAL Administrator screens
// for CASE-071..CASE-090 (Administrator Dashboard, Admin User Management,
// Heritage Site Management).
//
// Builds on heritagebot_fixtures.dart / contributor_flow.dart (unchanged).
// Like those helpers it only
//   * seeds Firestore documents in exactly the shape HeritageBot's own
//     services write them (UserService, HeritageSiteService,
//     UsageAnalyticsService, BookmarkService, AiNarrativeService),
//   * signs in through the real AuthGate, taps / types / scrolls the real
//     widgets from package:heritagebot/main.dart, and
//   * reads what those widgets display.
// It never renders a screen of its own and never decides a test result.
//
// ADMINISTRATOR ACCESS
// HeritageBot grants the Administrator role only to the e-mail addresses in
// UserService.adminEmails (lib/services/user_service.dart, read-only). The
// test administrator therefore uses the first address of that real list, but
// ONLY inside the in-memory FakeFirebaseAuthPlatform: no real Firebase
// account is used, contacted or changed, and the password is a test value.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:heritagebot/main.dart' as app;
import 'package:heritagebot/models/heritage_place.dart';
import 'package:heritagebot/models/user_profile.dart';
import 'package:heritagebot/services/user_service.dart';

import 'contributor_flow.dart' show shownSnackBarTexts;
import 'heritagebot_fixtures.dart';

export 'contributor_flow.dart' show shownSnackBarTexts;
export 'heritagebot_fixtures.dart';

// ---------------------------------------------------------------------------
// ACCOUNTS
// ---------------------------------------------------------------------------

/// Fake Firebase Auth account for the HeritageBot Administrator.
final FakeAuthAccount kAdminAccount = FakeAuthAccount(
  uid: 'case-admin-uid',
  email: UserService.adminEmails.first,
  password: 'AdminTest#2026',
  displayName: 'HeritageBot Test Administrator',
);

/// A registered HeritageBot account (users/{uid}) as the test seeds it.
class SeedUser {
  const SeedUser({
    required this.uid,
    required this.fullName,
    required this.email,
    required this.role,
    this.accountStatus = 'active',
    this.preferredLanguage = 'en',
    this.createdAtMillis = 1767225600000, // 2026-01-01
  });

  final String uid;
  final String fullName;
  final String email;
  final String role;
  final String accountStatus;
  final String preferredLanguage;
  final int createdAtMillis;
}

/// Seeds users/{uid} with the fields UserService.savePublicProfile writes.
void seedUser(HeritageBotTestBackend backend, SeedUser user) {
  backend.firestore.seedDocument('users/${user.uid}', <String, dynamic>{
    'uid': user.uid,
    'fullName': user.fullName,
    'email': user.email,
    'role': user.role,
    'preferredLanguage': user.preferredLanguage,
    'accountStatus': user.accountStatus,
    'photoUrl': '',
    'createdAtMillis': user.createdAtMillis,
    'updatedAtMillis': user.createdAtMillis,
  });
}

/// All users/{uid} documents currently stored (NOT sub-collections).
Map<String, Map<String, dynamic>> storedUsers(HeritageBotTestBackend backend) =>
    Map<String, Map<String, dynamic>>.fromEntries(
      backend.firestore.documents.entries.where(
        (e) => e.key.startsWith('users/') && e.key.split('/').length == 2,
      ),
    );

/// All heritage_sites/{id} documents currently stored.
Map<String, Map<String, dynamic>> storedSites(HeritageBotTestBackend backend) =>
    Map<String, Map<String, dynamic>>.fromEntries(
      backend.firestore.documents.entries.where(
        (e) => e.key.startsWith('heritage_sites/'),
      ),
    );

// ---------------------------------------------------------------------------
// ANALYTICS RECORDS
// ---------------------------------------------------------------------------

/// usage_events/{id} exactly as UsageAnalyticsService._record writes it.
void seedUsageEvent(
  HeritageBotTestBackend backend, {
  required String id,
  required String eventType, // site_view | navigation_start | dynamic_search
  HeritagePlace? site,
  String userId = 'fixture-tourist-uid',
  int createdAtMillis = 1767225600000,
}) {
  backend.firestore.seedDocument('usage_events/$id', <String, dynamic>{
    'eventType': eventType,
    'userId': userId,
    'userEmail': 'tourist@heritagebot.test',
    'createdAtMillis': createdAtMillis,
    if (site != null) ...<String, dynamic>{
      'siteId': site.id,
      'siteName': site.name,
      'siteLocation': site.location,
      'isTesting': site.isTesting,
    },
    if (eventType == 'dynamic_search') ...<String, dynamic>{
      'query': 'heritage near me',
      'resolvedLocation': 'Cebu City',
      'resultCount': 3,
    },
  });
}

/// users/{uid}/bookmarks/{siteId} exactly as BookmarkService.addBookmark
/// writes it.
void seedBookmark(
  HeritageBotTestBackend backend, {
  required String userUid,
  required HeritagePlace site,
}) {
  backend.firestore
      .seedDocument('users/$userUid/bookmarks/${site.id}', <String, dynamic>{
        'siteId': site.id,
        'siteName': site.name,
        'location': site.location,
        'isTesting': site.isTesting,
        'createdAtMillis': 1767225600000,
      });
}

/// ai_narratives/{id} exactly as AiNarrativeService.recordGeneratedNarrative
/// writes it.
void seedNarrative(
  HeritageBotTestBackend backend, {
  required String id,
  required HeritagePlace site,
}) {
  backend.firestore.seedDocument('ai_narratives/$id', <String, dynamic>{
    'userId': 'fixture-tourist-uid',
    'siteId': site.id,
    'siteName': site.name,
    'narrative': 'A short generated narrative about ${site.name}.',
    'languageCode': 'en',
    'modelName': 'gemini-test',
    'retrievalMode': 'knowledge_base',
    'retrievedContentIds': <String>[],
    'retrievedSourceTitles': <String>[],
    'distanceMeters': 12.0,
    'reviewStatus': 'pending_review',
    'adminReviewNote': '',
    'createdAtMillis': 1767225600000,
    'reviewedAtMillis': 0,
  });
}

// ---------------------------------------------------------------------------
// KNOWN APPLICATION DEFECT D1: duplicate FloatingActionButton hero tags
// ---------------------------------------------------------------------------
//
// AdminShell keeps all five admin tabs alive in an IndexedStack. Two of them
// - AdminHeritageSitesScreen ("Add Site") and AdminKnowledgeBaseScreen -
// use FloatingActionButton.extended without a heroTag, so both carry
// Flutter's <default FloatingActionButton tag>. Whenever a page route is
// pushed or popped over AdminShell (Manage Users, user details, the site
// editor), Flutter's Hero controller asserts:
//   "There are multiple heroes that share the same tag within a subtree."
// This is a real defect in lib/main.dart (debug builds report it on the
// device too; release builds compile asserts out). It is NOT fixed here.
//
// DEFAULT (strict): nothing is intercepted - Flutter reports the assertion
// and the test FAILS, exactly as flutter_test always does.
//
// OPT-IN: --dart-define=HERITAGEBOT_TOLERATE_HERO_TAG_DEFECT=true makes the
// helpers below take ONLY this exact assertion (any other exception is
// re-thrown and still fails the test) and print an
// "APPLICATION DEFECT OBSERVED" line for every occurrence, so the
// functional expected result of the test case can be judged on its own.

const bool kTolerateHeroTagDefect = bool.fromEnvironment(
  'HERITAGEBOT_TOLERATE_HERO_TAG_DEFECT',
);

/// Number of D1 assertions taken in this test run (tolerant mode only).
int heroTagDefectsObserved = 0;

bool _isDuplicateFabHeroTag(Object error) {
  final text = error.toString();
  return text.contains('multiple heroes that share the same tag') &&
      text.contains('<default FloatingActionButton tag>');
}

/// Call after a page route is pushed / popped over AdminShell.
void noteAdminShellHeroDefect(WidgetTester tester) {
  if (!kTolerateHeroTagDefect) return; // strict: Flutter fails the test
  final error = tester.takeException();
  if (error == null) return;
  if (!_isDuplicateFabHeroTag(error)) {
    throw error; // anything else is never tolerated
  }
  heroTagDefectsObserved++;
  // ignore: avoid_print
  print(
    'APPLICATION DEFECT OBSERVED (D1): AdminShell has two '
    'FloatingActionButtons with the default hero tag '
    '(AdminHeritageSitesScreen + AdminKnowledgeBaseScreen); Flutter '
    'asserted "multiple heroes that share the same tag" on a route '
    'transition. Occurrence #$heroTagDefectsObserved in this test.',
  );
}

// ---------------------------------------------------------------------------
// OPEN THE REAL ADMINISTRATOR UI
// ---------------------------------------------------------------------------

Finder get adminSummaryScreen => find.byType(app.AdminAnalyticsScreen);

/// Administrator already signed in -> real AuthGate -> UserService role
/// lookup -> AdminShell, waiting until the first tab (AdminAnalyticsScreen,
/// "Summary") finished AdminAnalyticsService.loadSnapshot().
Future<void> openAdminShell(WidgetTester tester) async {
  await signInBeforeLaunch(kAdminAccount);
  await launchAuthGate(tester, until: app.AdminShell);
  await waitForAdminSummary(tester);
}

/// Waits until AdminAnalyticsScreen shows its data OR its error card.
Future<void> waitForAdminSummary(WidgetTester tester) async {
  for (var i = 0; i < 100; i++) {
    await tester.pump(const Duration(milliseconds: 50));
    final loaded = find
        .descendant(of: adminSummaryScreen, matching: find.text('Total Users'))
        .evaluate()
        .isNotEmpty;
    final failed = infoCardsTitled(tester, 'Could Not Load Analytics')
        .isNotEmpty;
    if (loaded || failed) break;
  }
  await pumpFor(tester, const Duration(milliseconds: 300));
}

// ---------------------------------------------------------------------------
// READ THE SYSTEM SUMMARY / ANALYTICS SCREEN
// ---------------------------------------------------------------------------

/// What the real AdminAnalyticsScreen displays.
class AdminSummaryView {
  AdminSummaryView({
    required this.appBarTitle,
    required this.metrics,
    required this.sections,
    required this.otherCards,
  });

  final String? appBarTitle;

  /// Metric cards keyed by label, e.g. 'Total Users' -> ['6', 'Total Users',
  /// '5 active • 1 suspended'] (value, label, subtitle).
  final Map<String, List<String>> metrics;

  /// Analytics sections keyed by title, value = every text in the section in
  /// on-screen order (title, subtitle, rows...).
  final Map<String, List<String>> sections;

  /// Any other card (e.g. the "Generate PDF Report" tile) keyed by its
  /// first text.
  final Map<String, List<String>> otherCards;

  String? metricValue(String label) => metrics[label]?.first;
  String? metricSubtitle(String label) {
    final texts = metrics[label];
    return texts == null || texts.length < 3 ? null : texts[2];
  }

  /// Breakdown rows of a section ("label", "value" pairs after the header).
  Map<String, int> breakdown(String sectionTitle) {
    final texts = sections[sectionTitle];
    final rows = <String, int>{};
    if (texts == null) return rows;
    for (var i = 2; i + 1 < texts.length; i += 2) {
      final value = int.tryParse(texts[i + 1]);
      if (value == null) break;
      rows[texts[i]] = value;
    }
    return rows;
  }

  /// Ranking rows of a section: (rank, name, "N views"/"N bookmarks").
  List<List<String>> ranking(String sectionTitle) {
    final texts = sections[sectionTitle];
    final rows = <List<String>>[];
    if (texts == null) return rows;
    for (var i = 2; i + 2 < texts.length; i += 3) {
      if (int.tryParse(texts[i]) == null) break;
      rows.add([texts[i], texts[i + 1], texts[i + 2]]);
    }
    return rows;
  }

  @override
  String toString() =>
      'AdminSummaryView(appBar=$appBarTitle, metrics=$metrics, '
      'sections=$sections, otherCards=$otherCards)';
}

List<String> _textWidgetsUnder(WidgetTester tester, Finder scope) => tester
    .widgetList<Text>(find.descendant(of: scope, matching: find.byType(Text)))
    .map((t) => t.data ?? t.textSpan?.toPlainText() ?? '')
    .where((t) => t.isNotEmpty)
    .toList();

/// Scrolls the real AdminAnalyticsScreen from top to bottom (its ListView
/// builds lazily) and records every card it shows.
Future<AdminSummaryView> readAdminSummary(WidgetTester tester) async {
  final metrics = <String, List<String>>{};
  final sections = <String, List<String>>{};
  final others = <String, List<String>>{};

  void readVisibleCards() {
    for (final element
        in find
            .descendant(of: adminSummaryScreen, matching: find.byType(Card))
            .evaluate()) {
      final card = find.byElementPredicate((e) => e == element);
      final texts = _textWidgetsUnder(tester, card);
      if (texts.isEmpty) continue;
      final avatars = find
          .descendant(of: card, matching: find.byType(CircleAvatar))
          .evaluate()
          .length;
      final isMetric = texts.length == 3 && avatars == 1;
      if (isMetric) {
        metrics[texts[1]] = texts;
      } else if (texts.length >= 3) {
        sections[texts[0]] = texts;
      } else {
        others[texts[0]] = texts;
      }
    }
  }

  final scrollable = find
      .descendant(of: adminSummaryScreen, matching: find.byType(Scrollable))
      .first;
  final position = tester.state<ScrollableState>(scrollable).position;
  position.jumpTo(0);
  await tester.pump();
  for (var i = 0; i < 60; i++) {
    readVisibleCards();
    if (position.pixels >= position.maxScrollExtent) break;
    position.jumpTo(
      (position.pixels + 300).clamp(0, position.maxScrollExtent).toDouble(),
    );
    await tester.pump();
  }
  readVisibleCards();
  position.jumpTo(0);
  await tester.pump();

  final appBarTitles = _textWidgetsUnder(
    tester,
    find.descendant(of: adminSummaryScreen, matching: find.byType(AppBar)),
  );

  return AdminSummaryView(
    appBarTitle: appBarTitles.isEmpty ? null : appBarTitles.first,
    metrics: metrics,
    sections: sections,
    otherCards: others,
  );
}

// ---------------------------------------------------------------------------
// ADMIN USER MANAGEMENT
// ---------------------------------------------------------------------------

Finder get adminUsersScreen => find.byType(app.AdminUsersScreen);

/// AdminShell -> "Settings" tab -> "Manage Users" -> AdminUsersScreen with
/// UserService.getAllUsers() finished.
Future<void> openManageUsers(WidgetTester tester) async {
  await tapNavDestination(tester, 'Settings');
  final entry = find.descendant(
    of: find.byType(app.AdminSystemSettingsScreen),
    matching: find.text('Manage Users'),
  );
  await pumpUntilFound(tester, entry);
  await tapVisible(tester, entry);
  await pumpUntilFound(tester, adminUsersScreen);
  await waitForUserList(tester);
  noteAdminShellHeroDefect(tester);
}

Future<void> waitForUserList(WidgetTester tester) async {
  for (var i = 0; i < 100; i++) {
    await tester.pump(const Duration(milliseconds: 50));
    final loaded = find
        .descendant(
          of: adminUsersScreen,
          matching: find.text('Admin User Management'),
        )
        .evaluate()
        .isNotEmpty;
    if (loaded || infoCardsTitled(tester, 'Could Not Load Users').isNotEmpty) {
      break;
    }
  }
  await pumpFor(tester, const Duration(milliseconds: 300));
}

/// One account row exactly as AdminUsersScreen renders it.
class ListedUser {
  ListedUser({
    required this.name,
    required this.email,
    required this.roleLabel,
    required this.statusLabel,
  });

  final String name;
  final String email;
  final String roleLabel; // UserRoles.label(role)
  final String statusLabel; // accountStatus.toUpperCase()

  @override
  String toString() => 'ListedUser($name, $email, $roleLabel, $statusLabel)';
}

/// Every account card on AdminUsersScreen (scrolls the lazy list).
Future<List<ListedUser>> listedUsers(WidgetTester tester) async {
  final byEmail = <String, ListedUser>{};

  void readVisible() {
    for (final tile in tester.widgetList<ListTile>(
      find.descendant(of: adminUsersScreen, matching: find.byType(ListTile)),
    )) {
      final title = tile.title is Text ? (tile.title as Text).data ?? '' : '';
      final subtitleWidget = tile.subtitle is Padding
          ? (tile.subtitle as Padding).child
          : tile.subtitle;
      final subtitle = subtitleWidget is Text ? subtitleWidget.data ?? '' : '';
      final parts = subtitle.split('\n');
      if (parts.length != 2) continue;
      final roleStatus = parts[1].split(' • ');
      byEmail[parts[0]] = ListedUser(
        name: title,
        email: parts[0],
        roleLabel: roleStatus.first,
        statusLabel: roleStatus.length > 1 ? roleStatus[1] : '',
      );
    }
  }

  final scrollable = find
      .descendant(of: adminUsersScreen, matching: find.byType(Scrollable))
      .first;
  final position = tester.state<ScrollableState>(scrollable).position;
  position.jumpTo(0);
  await tester.pump();
  for (var i = 0; i < 60; i++) {
    readVisible();
    if (position.pixels >= position.maxScrollExtent) break;
    position.jumpTo(
      (position.pixels + 300).clamp(0, position.maxScrollExtent).toDouble(),
    );
    await tester.pump();
  }
  readVisible();
  position.jumpTo(0);
  await tester.pump();
  return byEmail.values.toList();
}

/// Types [query] into the real "Search Users" field.
Future<void> searchUsers(WidgetTester tester, String query) async {
  final field = find.descendant(
    of: adminUsersScreen,
    matching: find.byWidgetPredicate(
      (w) => w is TextField && w.decoration?.labelText == 'Search Users',
    ),
  );
  expect(field, findsOneWidget, reason: 'The "Search Users" field');
  await tester.enterText(field, query);
  await tester.pump();
  await pumpFor(tester, const Duration(milliseconds: 300));
}

/// Taps the account card whose subtitle starts with [email] and waits for
/// AdminUserDetailScreen.
Future<void> openUserCard(WidgetTester tester, String email) async {
  final tile = find.descendant(
    of: adminUsersScreen,
    matching: find.byWidgetPredicate((w) {
      if (w is! ListTile) return false;
      final sub = w.subtitle is Padding
          ? (w.subtitle as Padding).child
          : w.subtitle;
      return sub is Text && (sub.data ?? '').startsWith('$email\n');
    }),
  );
  await scrollUntilBuilt(tester, tile, screen: app.AdminUsersScreen);
  await tapVisible(tester, tile);
  await pumpUntilFound(tester, find.byType(app.AdminUserDetailScreen));
  await pumpFor(tester, const Duration(milliseconds: 300));
  noteAdminShellHeroDefect(tester);
}

/// Label -> value rows of the real AdminUserDetailScreen ("Email Address",
/// "User Role", "Preferred Language", "Account Created", "Account Status"),
/// plus 'title' = the SectionTitle heading.
Map<String, String> userDetailRows(WidgetTester tester) {
  final screen = find.byType(app.AdminUserDetailScreen);
  final texts = _textWidgetsUnder(tester, screen);
  const labels = [
    'Email Address',
    'User Role',
    'Preferred Language',
    'Account Created',
    'Account Status',
  ];
  final rows = <String, String>{};
  for (var i = 0; i + 1 < texts.length; i++) {
    if (labels.contains(texts[i]) && !rows.containsKey(texts[i])) {
      rows[texts[i]] = texts[i + 1];
    }
  }
  final heading = tester
      .widgetList<app.SectionTitle>(
        find.descendant(of: screen, matching: find.byType(app.SectionTitle)),
      )
      .map((s) => s.title)
      .toList();
  if (heading.isNotEmpty) rows['title'] = heading.first;
  return rows;
}

/// Labels of the buttons offered on AdminUserDetailScreen.
List<String> userDetailButtons(WidgetTester tester) => _textWidgetsUnder(
  tester,
  find.descendant(
    of: find.byType(app.AdminUserDetailScreen),
    matching: find.byWidgetPredicate((w) => w is ButtonStyleButton),
  ),
);

/// Back (AppBar / system back) from AdminUserDetailScreen to the list.
Future<void> backFromUserDetail(WidgetTester tester) async {
  final navigator = Navigator.of(
    tester.element(find.byType(app.AdminUserDetailScreen)),
  );
  await navigator.maybePop();
  await tester.pump();
  await pumpUntilGone(tester, find.byType(app.AdminUserDetailScreen));
  await pumpFor(tester, const Duration(milliseconds: 300));
  noteAdminShellHeroDefect(tester);
}

// ---------------------------------------------------------------------------
// HERITAGE SITE MANAGEMENT
// ---------------------------------------------------------------------------

Finder get adminSitesScreen => find.byType(app.AdminHeritageSitesScreen);
Finder get siteEditorScreen => find.byType(app.HeritageSiteEditorScreen);

/// AdminShell -> "Sites" tab -> AdminHeritageSitesScreen with
/// HeritageSiteService.getAllSites() finished.
Future<void> openAdminSites(WidgetTester tester) async {
  await tapNavDestination(tester, 'Sites');
  await waitForSiteList(tester);
}

Future<void> waitForSiteList(WidgetTester tester) async {
  for (var i = 0; i < 100; i++) {
    await tester.pump(const Duration(milliseconds: 50));
    final done =
        infoCardsTitled(tester, 'Firestore Connected').isNotEmpty ||
        infoCardsTitled(tester, 'Firestore Sites Not Initialized').isNotEmpty ||
        infoCardsTitled(tester, 'Could Not Load Heritage Sites').isNotEmpty;
    if (done) break;
  }
  await pumpFor(tester, const Duration(milliseconds: 300));
}

/// One site card exactly as AdminHeritageSitesScreen renders it.
class ListedSite {
  ListedSite({
    required this.name,
    required this.typeChip,
    required this.location,
    required this.coordinates,
    required this.active,
    required this.hasEdit,
    required this.hasDelete,
  });

  final String name;
  final String typeChip; // OFFICIAL / TEST SITE
  final String location;
  final String coordinates; // "Lat .. • Lng .. • Radius .. m"
  final bool active; // "Active in HeritageBot" switch value
  final bool hasEdit;
  final bool hasDelete;

  @override
  String toString() =>
      'ListedSite($name, $typeChip, $location, $coordinates, active=$active, '
      'edit=$hasEdit, delete=$hasDelete)';
}

/// Every site card on AdminHeritageSitesScreen (scrolls the lazy list).
Future<List<ListedSite>> listedSites(WidgetTester tester) async {
  final byName = <String, ListedSite>{};

  void readVisible() {
    for (final element
        in find
            .descendant(of: adminSitesScreen, matching: find.byType(Card))
            .evaluate()) {
      final card = find.byElementPredicate((e) => e == element);
      final switches = tester
          .widgetList<SwitchListTile>(
            find.descendant(of: card, matching: find.byType(SwitchListTile)),
          )
          .toList();
      if (switches.isEmpty) continue;
      final texts = _textWidgetsUnder(tester, card);
      if (texts.length < 4) continue;
      byName[texts[0]] = ListedSite(
        name: texts[0],
        typeChip: texts[1],
        location: texts[2],
        coordinates: texts[3],
        active: switches.first.value,
        hasEdit: texts.contains('Edit'),
        hasDelete: texts.contains('Delete'),
      );
    }
  }

  final scrollable = find
      .descendant(of: adminSitesScreen, matching: find.byType(Scrollable))
      .first;
  final position = tester.state<ScrollableState>(scrollable).position;
  position.jumpTo(0);
  await tester.pump();
  for (var i = 0; i < 60; i++) {
    readVisible();
    if (position.pixels >= position.maxScrollExtent) break;
    position.jumpTo(
      (position.pixels + 300).clamp(0, position.maxScrollExtent).toDouble(),
    );
    await tester.pump();
  }
  readVisible();
  position.jumpTo(0);
  await tester.pump();
  return byName.values.toList();
}

/// Taps "Edit" or "Delete" on the site card titled [siteName].
Future<void> tapSiteAction(
  WidgetTester tester, {
  required String siteName,
  required String action,
}) async {
  final title = find.descendant(
    of: adminSitesScreen,
    matching: find.text(siteName),
  );
  await scrollUntilBuilt(tester, title, screen: app.AdminHeritageSitesScreen);
  final card = find.ancestor(of: title, matching: find.byType(Card)).first;
  final button = find.descendant(of: card, matching: find.text(action));
  await tester.ensureVisible(button);
  await tester.pump();
  await tapVisible(tester, button);
}

/// Opens the real HeritageSiteEditorScreen: "Add Site" (FAB) when
/// [siteName] is null, otherwise the "Edit" button of that site's card.
Future<void> openSiteEditor(WidgetTester tester, {String? siteName}) async {
  if (siteName == null) {
    final add = find.descendant(
      of: adminSitesScreen,
      matching: find.text('Add Site'),
    );
    await tapVisible(tester, add);
  } else {
    await tapSiteAction(tester, siteName: siteName, action: 'Edit');
  }
  await pumpUntilFound(tester, siteEditorScreen);
  await pumpFor(tester, const Duration(milliseconds: 400));
  noteAdminShellHeroDefect(tester);
}

/// Taps "Save Heritage Site" and waits until the editor closed (saved) or a
/// message is shown while it stays open (rejected). Returns true when the
/// editor closed.
Future<bool> saveSiteEditor(WidgetTester tester) async {
  await tapSaveSite(tester);
  var closed = false;
  for (var i = 0; i < 100; i++) {
    await tester.pump(const Duration(milliseconds: 50));
    closed = siteEditorScreen.evaluate().isEmpty;
    if (closed || shownSnackBarTexts(tester).isNotEmpty) break;
  }
  await pumpFor(tester, const Duration(milliseconds: 600));
  closed = siteEditorScreen.evaluate().isEmpty;
  if (closed) {
    await waitForSiteList(tester);
    noteAdminShellHeroDefect(tester);
  }
  return closed;
}

/// The editor's TextField whose label is [label].
Finder editorField(String label) => find.descendant(
  of: siteEditorScreen,
  matching: find.byWidgetPredicate(
    (w) => w is TextField && w.decoration?.labelText == label,
  ),
);

/// Current text of an editor field (scrolls it into the built range).
Future<String> readEditorField(WidgetTester tester, String label) async {
  final field = editorField(label);
  await scrollUntilBuilt(tester, field, screen: app.HeritageSiteEditorScreen);
  return tester.widget<TextField>(field).controller?.text ?? '';
}

/// Types [value] into the editor field labelled [label].
Future<void> enterEditorField(
  WidgetTester tester,
  String label,
  String value,
) async {
  final field = editorField(label);
  await scrollUntilBuilt(tester, field, screen: app.HeritageSiteEditorScreen);
  await tester.ensureVisible(field);
  await tester.pump();
  await tester.enterText(field, value);
  await tester.pump();
}

/// Taps "Save Heritage Site" on the real editor.
Future<void> tapSaveSite(WidgetTester tester) async {
  final save = find.descendant(
    of: siteEditorScreen,
    matching: find.text('Save Heritage Site'),
  );
  await scrollUntilBuilt(tester, save, screen: app.HeritageSiteEditorScreen);
  await tapVisible(tester, save);
}

/// Taps a button of the currently shown AlertDialog by its label.
Future<void> tapDialogButton(WidgetTester tester, String label) async {
  final button = find.descendant(
    of: find.byType(AlertDialog),
    matching: find.text(label),
  );
  expect(button, findsOneWidget, reason: 'Dialog button "$label"');
  await tester.tap(button);
  await tester.pump();
}

// ---------------------------------------------------------------------------
// GENERIC SCREEN TEXT (for access checks)
// ---------------------------------------------------------------------------

/// Every text the real [screen] builds, scrolling its primary list from top
/// to bottom so lazily built entries are included.
Future<Set<String>> allTextsOfScreen(WidgetTester tester, Finder screen) async {
  final texts = <String>{...textsUnder(tester, screen)};
  final scrollables = find.descendant(
    of: screen,
    matching: find.byType(Scrollable),
  );
  if (scrollables.evaluate().isEmpty) return texts;
  final state = tester.state<ScrollableState>(scrollables.first);
  if (state.position.axis != Axis.vertical) return texts;
  final position = state.position;
  position.jumpTo(0);
  await tester.pump();
  for (var i = 0; i < 60; i++) {
    texts.addAll(textsUnder(tester, screen));
    if (position.pixels >= position.maxScrollExtent) break;
    position.jumpTo(
      (position.pixels + 300).clamp(0, position.maxScrollExtent).toDouble(),
    );
    await tester.pump();
  }
  position.jumpTo(0);
  await tester.pump();
  return texts;
}

/// Label used by UserRoles for [role] (re-exported for readability).
String roleLabel(String role) => UserRoles.label(role);
