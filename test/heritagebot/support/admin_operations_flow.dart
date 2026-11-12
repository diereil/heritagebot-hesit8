// HERITAGEBOT - TEST SUPPORT: drives and reads the REAL Administrator
// "Review", "AI Base" and "Settings" tabs for CASE-091..CASE-120
// (Community Contribution Review, AI Knowledge Base Management, System
// Settings).
//
// Builds on admin_flow.dart (unchanged). Like the other helpers it only
//   * seeds Firestore documents in exactly the shape HeritageBot's own
//     services write them (HistoricalContent.toMap, HeritageBotSystemSettings
//     / SystemSettingsService.saveSettings, CommunitySubmission.toMap),
//   * taps / types / scrolls the real widgets from package:heritagebot/main.dart,
//   * reads what those widgets display.
// It never renders a screen of its own and never decides a test result.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:heritagebot/main.dart' as app;
import 'package:heritagebot/models/heritage_place.dart';
import 'package:heritagebot/models/historical_content.dart';
import 'package:heritagebot/services/gemini_embedding_service.dart';

import 'admin_flow.dart';

export 'admin_flow.dart';

// ---------------------------------------------------------------------------
// GENERIC
// ---------------------------------------------------------------------------

/// Texts of every Card built under [screen], scrolling its first vertical
/// scrollable from top to bottom so lazily built cards are included. Cards
/// are keyed by their first text (de-duplicated across scroll positions).
Future<List<List<String>>> cardTextsOf(WidgetTester tester, Finder screen) async {
  final byFirst = <String, List<String>>{};

  void readVisible() {
    for (final element
        in find.descendant(of: screen, matching: find.byType(Card)).evaluate()) {
      final card = find.byElementPredicate((e) => e == element);
      final texts = tester
          .widgetList<Text>(find.descendant(of: card, matching: find.byType(Text)))
          .map((t) => t.data ?? t.textSpan?.toPlainText() ?? '')
          .where((t) => t.isNotEmpty)
          .toList();
      if (texts.isNotEmpty) byFirst[texts.first] = texts;
    }
  }

  final scrollables = find.descendant(of: screen, matching: find.byType(Scrollable));
  if (scrollables.evaluate().isEmpty) {
    readVisible();
    return byFirst.values.toList();
  }
  final state = tester.state<ScrollableState>(scrollables.first);
  final position = state.position;
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
  return byFirst.values.toList();
}

/// True when [screen] currently builds a Text whose value is [text].
bool screenShowsText(Finder screen, String text) => find
    .descendant(of: screen, matching: find.text(text), skipOffstage: false)
    .evaluate()
    .isNotEmpty;

// ---------------------------------------------------------------------------
// REVIEW TAB (AdminDashboardScreen / AdminReviewSubmissionScreen)
// ---------------------------------------------------------------------------

Finder get reviewQueueScreen => find.byType(app.AdminDashboardScreen);
Finder get reviewDetailScreen => find.byType(app.AdminReviewSubmissionScreen);

/// AdminShell -> "Review" -> AdminDashboardScreen with getAllSubmissions()
/// finished (list OR error card).
Future<void> openReviewTab(WidgetTester tester) async {
  await tapNavDestination(tester, 'Review');
  await waitForReviewQueue(tester);
}

Future<void> waitForReviewQueue(WidgetTester tester) async {
  for (var i = 0; i < 100; i++) {
    await tester.pump(const Duration(milliseconds: 50));
    final loaded = find
        .descendant(
          of: reviewQueueScreen,
          matching: find.textContaining('Read submitted heritage stories'),
        )
        .evaluate()
        .isNotEmpty;
    if (loaded || infoCardsTitled(tester, 'Could Not Load Contributions').isNotEmpty) {
      break;
    }
  }
  await pumpFor(tester, const Duration(milliseconds: 300));
}

/// One submission card exactly as AdminDashboardScreen renders it:
/// title, heritage place, timestamp, "Contributor: ...", e-mail, story
/// (max 4 lines), status chip.
class ReviewQueueCard {
  ReviewQueueCard(this.texts);

  final List<String> texts;

  String get title => texts.first;
  String get placeName => texts.length > 1 ? texts[1] : '';
  String get statusLabel => texts.last;
  String? get contributorLine =>
      texts.where((t) => t.startsWith('Contributor: ')).firstOrNull;

  @override
  String toString() => 'ReviewQueueCard($texts)';
}

/// Every submission card on the review queue (InfoCards excluded).
Future<List<ReviewQueueCard>> reviewQueueCards(WidgetTester tester) async {
  final cards = await cardTextsOf(tester, reviewQueueScreen);
  return cards
      .where((texts) => texts.any((t) => t.startsWith('Contributor: ')))
      .map(ReviewQueueCard.new)
      .toList();
}

/// Value of the "label: N" summary chip on the review queue (null if absent).
int? reviewSummaryCount(String label) {
  final match = find
      .descendant(
        of: reviewQueueScreen,
        matching: find.byWidgetPredicate(
          (w) => w is Text && (w.data ?? '').startsWith('$label: '),
        ),
      )
      .evaluate();
  if (match.isEmpty) return null;
  final text = (match.first.widget as Text).data!;
  return int.tryParse(text.substring(label.length + 2));
}

/// Taps the status filter chip ("All", "Pending", "Approved", "Rejected").
Future<void> tapReviewFilter(WidgetTester tester, String label) async {
  final chip = find.descendant(
    of: reviewQueueScreen,
    matching: find.widgetWithText(ChoiceChip, label),
  );
  await tapVisible(tester, chip);
  await pumpFor(tester, const Duration(milliseconds: 300));
}

/// Taps the queue card titled [title] and waits for the real
/// AdminReviewSubmissionScreen.
Future<void> openReviewCard(WidgetTester tester, String title) async {
  final titleFinder = find.descendant(
    of: reviewQueueScreen,
    matching: find.text(title),
  );
  await scrollUntilBuilt(tester, titleFinder, screen: app.AdminDashboardScreen);
  final card = find.ancestor(of: titleFinder, matching: find.byType(InkWell)).first;
  await tester.ensureVisible(card);
  await tester.pump();
  await tester.tap(card);
  await tester.pump();
  await pumpUntilFound(tester, reviewDetailScreen);
  await pumpFor(tester, const Duration(milliseconds: 400));
  noteAdminShellHeroDefect(tester);
}

/// Types [feedback] into the "Administrator Feedback" field.
Future<void> enterReviewFeedback(WidgetTester tester, String feedback) async {
  final field = find.descendant(
    of: reviewDetailScreen,
    matching: find.byWidgetPredicate(
      (w) => w is TextField && w.decoration?.labelText == 'Administrator Feedback',
    ),
  );
  await scrollUntilBuilt(tester, field, screen: app.AdminReviewSubmissionScreen);
  await tester.ensureVisible(field);
  await tester.pump();
  await tester.enterText(field, feedback);
  await tester.pump();
}

/// Taps "Approve" or "Reject" on the review screen and waits until the
/// screen closed (saved) or a message is shown while it stays open.
/// Returns true when the review screen closed.
Future<bool> tapReviewDecision(WidgetTester tester, String label) async {
  final button = find.descendant(of: reviewDetailScreen, matching: find.text(label));
  await scrollUntilBuilt(tester, button, screen: app.AdminReviewSubmissionScreen);
  await tester.ensureVisible(button);
  await tester.pump();
  await tapVisible(tester, button);
  var closed = false;
  for (var i = 0; i < 100; i++) {
    await tester.pump(const Duration(milliseconds: 50));
    closed = reviewDetailScreen.evaluate().isEmpty;
    if (closed || shownSnackBarTexts(tester).isNotEmpty) break;
  }
  await pumpFor(tester, const Duration(milliseconds: 600));
  closed = reviewDetailScreen.evaluate().isEmpty;
  if (closed) {
    noteAdminShellHeroDefect(tester);
    await waitForReviewQueue(tester);
  }
  return closed;
}

// ---------------------------------------------------------------------------
// AI BASE TAB (AdminKnowledgeBaseScreen / HistoricalContentEditorScreen)
// ---------------------------------------------------------------------------

Finder get knowledgeBaseScreen => find.byType(app.AdminKnowledgeBaseScreen);
Finder get historicalEditorScreen => find.byType(app.HistoricalContentEditorScreen);

/// historical_contents/{id} exactly as KnowledgeBaseService.addContent
/// writes it (HistoricalContent.toMap).
HistoricalContent historicalRecord({
  required String id,
  required HeritagePlace site,
  required String title,
  required String content,
  required String sourceTitle,
  String sourceUrl = '',
  String category = 'historical_record',
  String sourceType = 'curated',
  String sourceRefId = '',
  bool isApproved = true,
  List<double> embedding = const <double>[],
  int updatedAtMillis = 1767225600000,
}) {
  return HistoricalContent(
    id: id,
    siteId: site.id,
    siteName: site.name,
    title: title,
    content: content,
    sourceTitle: sourceTitle,
    sourceUrl: sourceUrl,
    category: category,
    languageCode: 'en',
    sourceType: sourceType,
    sourceRefId: sourceRefId,
    isApproved: isApproved,
    embedding: embedding,
    embeddingModel: embedding.isEmpty ? '' : GeminiEmbeddingService.modelName,
    createdAtMillis: updatedAtMillis,
    updatedAtMillis: updatedAtMillis,
  );
}

void seedHistorical(HeritageBotTestBackend backend, HistoricalContent item) {
  backend.firestore.seedDocument('historical_contents/${item.id}', item.toMap());
}

/// All historical_contents documents currently stored.
Map<String, Map<String, dynamic>> storedHistorical(HeritageBotTestBackend backend) =>
    Map<String, Map<String, dynamic>>.fromEntries(
      backend.firestore.documents.entries
          .where((e) => e.key.startsWith('historical_contents/')),
    );

/// AdminShell -> "AI Base" -> AdminKnowledgeBaseScreen with getAllContent()
/// finished (list OR error card).
Future<void> openKnowledgeBaseTab(WidgetTester tester) async {
  await tapNavDestination(tester, 'AI Base');
  await waitForKnowledgeBase(tester);
}

Future<void> waitForKnowledgeBase(WidgetTester tester) async {
  for (var i = 0; i < 100; i++) {
    await tester.pump(const Duration(milliseconds: 50));
    final done = infoCardsTitled(tester, 'Vector Data Status').isNotEmpty ||
        infoCardsTitled(tester, 'Could Not Load Knowledge Base').isNotEmpty;
    if (done) break;
  }
  await pumpFor(tester, const Duration(milliseconds: 300));
}

/// One record card exactly as AdminKnowledgeBaseScreen renders it:
/// title, site name, content (max 4 lines), "Source: ...", type line,
/// Edit, Delete.
class KnowledgeCard {
  KnowledgeCard(this.texts);

  final List<String> texts;

  String get title => texts.first;
  String get siteName => texts.length > 1 ? texts[1] : '';
  String get content => texts.length > 2 ? texts[2] : '';
  String? get sourceLine => texts.where((t) => t.startsWith('Source: ')).firstOrNull;
  String? get detailLine => texts.where((t) => t.contains(' • ')).firstOrNull;

  @override
  String toString() => 'KnowledgeCard($texts)';
}

Future<List<KnowledgeCard>> knowledgeCards(WidgetTester tester) async {
  final cards = await cardTextsOf(tester, knowledgeBaseScreen);
  return cards
      .where((texts) => texts.any((t) => t.startsWith('Source: ')))
      .map(KnowledgeCard.new)
      .toList();
}

/// Value of a summary box ("Records", "Approved", "Vector Ready",
/// "Community"): the number Text directly above the label Text.
int? knowledgeSummaryValue(WidgetTester tester, String label) {
  final labelFinder = find.descendant(of: knowledgeBaseScreen, matching: find.text(label));
  if (labelFinder.evaluate().isEmpty) return null;
  final column = find.ancestor(of: labelFinder.first, matching: find.byType(Column)).first;
  final texts = tester
      .widgetList<Text>(find.descendant(of: column, matching: find.byType(Text)))
      .map((t) => t.data ?? '')
      .toList();
  final index = texts.indexOf(label);
  return index > 0 ? int.tryParse(texts[index - 1]) : null;
}

/// FAB "Add Historical Data" -> HistoricalContentEditorScreen.
Future<void> openAddHistoricalData(WidgetTester tester) async {
  final fab = find.descendant(
    of: knowledgeBaseScreen,
    matching: find.text('Add Historical Data'),
  );
  await tapVisible(tester, fab);
  await pumpUntilFound(tester, historicalEditorScreen);
  await pumpFor(tester, const Duration(milliseconds: 400));
  noteAdminShellHeroDefect(tester);
}

/// "Edit" on the knowledge card titled [title] -> editor.
Future<void> openEditHistoricalData(WidgetTester tester, String title) async {
  final titleFinder = find.descendant(of: knowledgeBaseScreen, matching: find.text(title));
  await scrollUntilBuilt(tester, titleFinder, screen: app.AdminKnowledgeBaseScreen);
  final card = find.ancestor(of: titleFinder, matching: find.byType(Card)).first;
  final edit = find.descendant(of: card, matching: find.text('Edit'));
  await tester.ensureVisible(edit);
  await tester.pump();
  await tapVisible(tester, edit);
  await pumpUntilFound(tester, historicalEditorScreen);
  await pumpFor(tester, const Duration(milliseconds: 400));
  noteAdminShellHeroDefect(tester);
}

Finder historicalEditorField(String label) => find.descendant(
  of: historicalEditorScreen,
  matching: find.byWidgetPredicate(
    (w) => w is TextField && w.decoration?.labelText == label,
  ),
);

Future<String> readHistoricalField(WidgetTester tester, String label) async {
  final field = historicalEditorField(label);
  await scrollUntilBuilt(tester, field, screen: app.HistoricalContentEditorScreen);
  return tester.widget<TextField>(field).controller?.text ?? '';
}

Future<void> enterHistoricalField(WidgetTester tester, String label, String value) async {
  final field = historicalEditorField(label);
  await scrollUntilBuilt(tester, field, screen: app.HistoricalContentEditorScreen);
  await tester.ensureVisible(field);
  await tester.pump();
  await tester.enterText(field, value);
  await tester.pump();
}

/// Opens the editor's "Heritage Site" dropdown and picks [siteName].
Future<void> chooseHistoricalSite(WidgetTester tester, String siteName) async {
  final dropdown = find
      .descendant(
        of: historicalEditorScreen,
        matching: find.byType(DropdownButtonFormField<String>),
      )
      .first;
  await tester.ensureVisible(dropdown);
  await tester.pump();
  await tester.tap(dropdown);
  await pumpFor(tester, const Duration(milliseconds: 400));
  await tester.tap(find.text(siteName).last);
  await pumpFor(tester, const Duration(milliseconds: 400));
}

/// Taps "Save & Generate Embedding" and waits until the editor closed or a
/// message is shown while it stays open. Returns true when it closed.
Future<bool> saveHistoricalEditor(WidgetTester tester) async {
  final save = find.descendant(
    of: historicalEditorScreen,
    matching: find.text('Save & Generate Embedding'),
  );
  await scrollUntilBuilt(tester, save, screen: app.HistoricalContentEditorScreen);
  await tapVisible(tester, save);
  var closed = false;
  for (var i = 0; i < 100; i++) {
    await tester.pump(const Duration(milliseconds: 50));
    closed = historicalEditorScreen.evaluate().isEmpty;
    if (closed || shownSnackBarTexts(tester).isNotEmpty) break;
  }
  await pumpFor(tester, const Duration(milliseconds: 600));
  closed = historicalEditorScreen.evaluate().isEmpty;
  if (closed) {
    noteAdminShellHeroDefect(tester);
    await waitForKnowledgeBase(tester);
  }
  return closed;
}

/// Taps a button of the AI Base screen by its label (e.g.
/// "Update Knowledge Base") and waits until the work finished.
Future<void> tapKnowledgeBaseAction(WidgetTester tester, String label) async {
  final button = find.descendant(of: knowledgeBaseScreen, matching: find.text(label));
  await scrollUntilBuilt(tester, button, screen: app.AdminKnowledgeBaseScreen);
  await tapVisible(tester, button);
  for (var i = 0; i < 200; i++) {
    await tester.pump(const Duration(milliseconds: 50));
    if (infoCardsTitled(tester, 'Updating Knowledge Base').isEmpty &&
        shownSnackBarTexts(tester).isNotEmpty) {
      break;
    }
  }
  await waitForKnowledgeBase(tester);
}

// ---------------------------------------------------------------------------
// SETTINGS TAB (AdminSystemSettingsScreen)
// ---------------------------------------------------------------------------

Finder get settingsScreen => find.byType(app.AdminSystemSettingsScreen);

/// system_settings/general exactly as SystemSettingsService.saveSettings
/// and createDatabaseBackup write it.
void seedSystemSettings(
  HeritageBotTestBackend backend, {
  required List<String> enabledLanguageCodes,
  required bool notificationsEnabled,
  int? lastBackupAtMillis,
  String lastBackupFileName = '',
  int lastBackupRecordCount = 0,
}) {
  backend.firestore.seedDocument('system_settings/general', <String, dynamic>{
    'enabledLanguageCodes': List<String>.of(enabledLanguageCodes)..sort(),
    'notificationsEnabled': notificationsEnabled,
    'updatedAtMillis': 1767225600000,
    'updatedByEmail': kAdminAccount.email,
    if (lastBackupAtMillis != null) ...<String, dynamic>{
      'lastBackupAtMillis': lastBackupAtMillis,
      'lastBackupFileName': lastBackupFileName,
      'lastBackupRecordCount': lastBackupRecordCount,
      'lastBackupByEmail': kAdminAccount.email,
    },
  });
}

Map<String, dynamic>? storedSettings(HeritageBotTestBackend backend) =>
    backend.firestore.documents['system_settings/general'];

/// AdminShell -> "Settings" -> AdminSystemSettingsScreen with getSettings()
/// finished (form OR "System Settings Unavailable").
Future<void> openSettingsTab(WidgetTester tester) async {
  await tapNavDestination(tester, 'Settings');
  await waitForSettings(tester);
}

Future<void> waitForSettings(WidgetTester tester) async {
  for (var i = 0; i < 100; i++) {
    await tester.pump(const Duration(milliseconds: 50));
    final loaded = screenShowsText(settingsScreen, 'Backup and System Settings');
    if (loaded || infoCardsTitled(tester, 'System Settings Unavailable').isNotEmpty) {
      break;
    }
  }
  await pumpFor(tester, const Duration(milliseconds: 300));
}

Finder languageCheckbox(String languageName) => find.descendant(
  of: settingsScreen,
  matching: find.byWidgetPredicate(
    (w) => w is CheckboxListTile && w.title is Text && (w.title as Text).data == languageName,
  ),
  skipOffstage: false,
);

/// Language name -> (checked, enabled) as the real CheckboxListTiles show.
Future<Map<String, ({bool checked, bool enabled})>> languageCheckboxStates(
  WidgetTester tester,
) async {
  final states = <String, ({bool checked, bool enabled})>{};
  final scrollable = find.descendant(of: settingsScreen, matching: find.byType(Scrollable)).first;
  final position = tester.state<ScrollableState>(scrollable).position;
  position.jumpTo(0);
  await tester.pump();
  for (var i = 0; i < 40; i++) {
    for (final tile in tester.widgetList<CheckboxListTile>(
      find.descendant(of: settingsScreen, matching: find.byType(CheckboxListTile)),
    )) {
      final name = tile.title is Text ? (tile.title as Text).data ?? '' : '';
      states[name] = (checked: tile.value == true, enabled: tile.onChanged != null);
    }
    if (position.pixels >= position.maxScrollExtent) break;
    position.jumpTo((position.pixels + 300).clamp(0, position.maxScrollExtent).toDouble());
    await tester.pump();
  }
  position.jumpTo(0);
  await tester.pump();
  return states;
}

Future<void> tapLanguageCheckbox(WidgetTester tester, String languageName) async {
  final tile = languageCheckbox(languageName);
  await scrollUntilBuilt(tester, tile, screen: app.AdminSystemSettingsScreen);
  await tester.ensureVisible(tile);
  await tester.pump();
  await tester.tap(tile);
  await tester.pump();
}

Finder get notificationSwitch => find.descendant(
  of: settingsScreen,
  matching: find.byWidgetPredicate(
    (w) =>
        w is SwitchListTile &&
        w.title is Text &&
        (w.title as Text).data == 'Notification Settings',
  ),
);

Future<bool> readNotificationSwitch(WidgetTester tester) async {
  await scrollUntilBuilt(tester, notificationSwitch, screen: app.AdminSystemSettingsScreen);
  return tester.widget<SwitchListTile>(notificationSwitch).value;
}

Future<void> tapNotificationSwitch(WidgetTester tester) async {
  await scrollUntilBuilt(tester, notificationSwitch, screen: app.AdminSystemSettingsScreen);
  await tester.ensureVisible(notificationSwitch);
  await tester.pump();
  await tester.tap(notificationSwitch);
  await tester.pump();
}

/// Taps a button on the Settings screen by its label ("Save Settings",
/// "Backup Database") and waits for a SnackBar (or [maxPumps]).
Future<void> tapSettingsButton(WidgetTester tester, String label) async {
  final button = find.descendant(of: settingsScreen, matching: find.text(label));
  await scrollUntilBuilt(tester, button, screen: app.AdminSystemSettingsScreen);
  await tester.ensureVisible(button);
  await tester.pump();
  await tapVisible(tester, button);
}

/// Taps the AppBar "Refresh" of the Settings screen (reloads from Firestore).
Future<void> refreshSettings(WidgetTester tester) async {
  final refresh = find.descendant(
    of: settingsScreen,
    matching: find.byTooltip('Refresh'),
  );
  await tapVisible(tester, refresh);
  await waitForSettings(tester);
}

/// Every Text the Settings screen builds (scrolls the form).
Future<Set<String>> settingsTexts(WidgetTester tester) =>
    allTextsOfScreen(tester, settingsScreen);
