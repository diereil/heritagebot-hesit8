// HERITAGEBOT - TEST SUPPORT: drives and reads the real Contributor
// dashboard and Profile screens for CASE-051..CASE-070.
//
// Builds on heritagebot_fixtures.dart / story_submission_flow.dart
// (unchanged). It only taps, types, scrolls and reads what the REAL widgets
// from package:heritagebot/main.dart display; it never decides a result.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:heritagebot/main.dart' as app;
import 'package:heritagebot/models/community_submission.dart';

import 'heritagebot_fixtures.dart';

// ---------------------------------------------------------------------------
// CONTRIBUTOR DASHBOARD ("Contribute" tab -> My Submissions)
// ---------------------------------------------------------------------------

/// AuthGate -> MainShell(contributor) -> "Contribute" ->
/// ContributorDashboardScreen with getMySubmissions() finished.
Future<void> openContributorDashboard(WidgetTester tester) async {
  await launchAuthGate(tester, until: app.MainShell);
  await tapNavDestination(tester, 'Contribute');
  await pumpUntilFound(tester, find.byType(app.ContributorDashboardScreen));
  await pumpUntilFound(
    tester,
    find.descendant(
      of: find.byType(app.ContributorDashboardScreen),
      matching: find.text('My Submissions'),
    ),
  );
  await pumpFor(tester, const Duration(milliseconds: 300));
}

/// One submission card exactly as ContributorDashboardScreen renders it.
class DashboardCard {
  DashboardCard({
    required this.title,
    required this.placeName,
    required this.statusLabel,
    required this.feedbackText,
    required this.hasEdit,
    required this.hasDelete,
    required this.texts,
  });

  final String title;
  final String placeName;
  final String statusLabel; // "Pending" / "Approved" / "Rejected"
  final String? feedbackText; // "Admin Feedback: ..." line, if shown
  final bool hasEdit;
  final bool hasDelete;
  final List<String> texts;

  @override
  String toString() =>
      'DashboardCard(title=$title, place=$placeName, '
      'status=$statusLabel, feedback=$feedbackText, edit=$hasEdit, '
      'delete=$hasDelete)';
}

const Set<String> _statusLabels = {'Pending', 'Approved', 'Rejected'};

Finder get _dashboard => find.byType(app.ContributorDashboardScreen);

List<DashboardCard> _visibleDashboardCards(WidgetTester tester) {
  final cards = <DashboardCard>[];
  for (final element
      in find
          .descendant(of: _dashboard, matching: find.byType(Card))
          .evaluate()) {
    final card = find.byElementPredicate((e) => e == element);
    final texts = tester
        .widgetList<Text>(
          find.descendant(of: card, matching: find.byType(Text)),
        )
        .map((t) => t.data ?? t.textSpan?.toPlainText() ?? '')
        .where((t) => t.isNotEmpty)
        .toList();
    // Submission card layout: title, heritage place, status chip, story...
    // (InfoCards on the same screen have no status chip.)
    if (texts.length < 3 || !_statusLabels.contains(texts[2])) continue;
    final feedback = texts.where((t) => t.startsWith('Admin Feedback: '));
    cards.add(
      DashboardCard(
        title: texts[0],
        placeName: texts[1],
        statusLabel: texts[2],
        feedbackText: feedback.isEmpty ? null : feedback.first,
        hasEdit: texts.contains('Edit'),
        hasDelete: texts.contains('Delete'),
        texts: texts,
      ),
    );
  }
  return cards;
}

/// Every submission card on the dashboard (scrolls the real list from top
/// to bottom so lazily built cards are included), keyed by title.
Future<Map<String, DashboardCard>> collectDashboardCards(
  WidgetTester tester,
) async {
  final scrollable = find
      .descendant(of: _dashboard, matching: find.byType(Scrollable))
      .first;
  final position = tester.state<ScrollableState>(scrollable).position;
  position.jumpTo(0);
  await tester.pump();

  final byTitle = <String, DashboardCard>{};
  for (var i = 0; i < 30; i++) {
    for (final card in _visibleDashboardCards(tester)) {
      byTitle[card.title] = card;
    }
    if (position.pixels >= position.maxScrollExtent) break;
    position.jumpTo(
      (position.pixels + 250).clamp(0, position.maxScrollExtent).toDouble(),
    );
    await tester.pump();
  }
  position.jumpTo(0);
  await tester.pump();
  return byTitle;
}

/// Taps the "Edit" or "Delete" button on the dashboard card titled [title].
Future<void> tapCardAction(
  WidgetTester tester, {
  required String title,
  required String action, // 'Edit' or 'Delete'
}) async {
  final titleFinder = find.descendant(
    of: _dashboard,
    matching: find.text(title),
  );
  await scrollUntilBuilt(
    tester,
    titleFinder,
    screen: app.ContributorDashboardScreen,
  );
  final card = find
      .ancestor(of: titleFinder, matching: find.byType(Card))
      .first;
  final button = find.descendant(of: card, matching: find.text(action));
  await tester.ensureVisible(button);
  await tester.pump();
  await tapVisible(tester, button);
}

/// Maps a status label shown on screen back to the stored status value.
String? statusForLabel(String label) {
  for (final status in const [
    CommunitySubmissionStatus.pending,
    CommunitySubmissionStatus.approved,
    CommunitySubmissionStatus.rejected,
  ]) {
    if (CommunitySubmissionStatus.label(status) == label) return status;
  }
  return null;
}

/// Opens the Heritage Place dropdown on [screen] and picks [placeName].
Future<void> chooseHeritagePlace(
  WidgetTester tester, {
  required Type screen,
  required String placeName,
}) async {
  final dropdown = find.descendant(
    of: find.byType(screen),
    matching: find.byType(DropdownButtonFormField<String>),
  );
  await tapVisible(tester, dropdown);
  await pumpFor(tester, const Duration(milliseconds: 400));
  // The open menu shows every item; the last match is the menu entry.
  await tester.tap(find.text(placeName).last);
  await pumpFor(tester, const Duration(milliseconds: 400));
}

// ---------------------------------------------------------------------------
// PROFILE TAB
// ---------------------------------------------------------------------------

/// MainShell -> Profile tab -> ProfileScreen with its role badge loaded.
Future<void> openProfileTab(WidgetTester tester) async {
  await tapNavDestination(tester, en('profile'));
  await pumpUntilFound(tester, find.byType(app.ProfileScreen));
  await pumpFor(tester, const Duration(milliseconds: 400));
}

Finder get profileScreen => find.byType(app.ProfileScreen);

/// Every Text currently built on the Profile screen.
List<String> profileTexts(WidgetTester tester) => tester
    .widgetList<Text>(
      find.descendant(
        of: profileScreen,
        matching: find.byType(Text),
        skipOffstage: false,
      ),
    )
    .map((t) => t.data ?? t.textSpan?.toPlainText() ?? '')
    .where((t) => t.isNotEmpty)
    .toList();

/// What happened when the test tried to change profile details through the
/// real Profile screen (CASE-066 / CASE-067).
class ProfileEditAttempt {
  ProfileEditAttempt({
    required this.profileActions,
    required this.editEntry,
    required this.editableFieldCount,
    required this.saveAction,
    required this.messages,
    required this.fieldErrors,
  });

  /// Labels of every button / list entry the Profile screen offers.
  final List<String> profileActions;

  /// The "edit profile"-type entry that was tapped (null = none offered).
  final String? editEntry;

  /// Editable text fields found for profile details (0 = no edit form).
  final int editableFieldCount;

  /// The save/update button that was tapped (null = none found).
  final String? saveAction;

  /// SnackBar messages shown after saving.
  final List<String> messages;

  /// Field-level validation errors (InputDecoration.errorText) shown.
  final List<String> fieldErrors;

  @override
  String toString() =>
      'ProfileEditAttempt(profileActions=$profileActions, '
      'editEntry=$editEntry, editableFieldCount=$editableFieldCount, '
      'saveAction=$saveAction, messages=$messages, fieldErrors=$fieldErrors)';
}

final RegExp _editEntryPattern = RegExp(
  r'edit profile|update profile|edit details|edit account|manage profile|'
  r'edit name|personal (info|details)|account details',
  caseSensitive: false,
);
final RegExp _saveActionPattern = RegExp(
  r'^(save|update|submit)',
  caseSensitive: false,
);

List<String> _actionLabels(WidgetTester tester, Finder scope) {
  final labels = <String>[];
  final buttons = find.descendant(
    of: scope,
    matching: find.byWidgetPredicate(
      (w) => w is ButtonStyleButton || w is ListTile || w is IconButton,
    ),
  );
  for (final element in buttons.evaluate()) {
    final widget = element.widget;
    if (widget is IconButton) {
      if (widget.tooltip != null) labels.add(widget.tooltip!);
      continue;
    }
    final texts = tester
        .widgetList<Text>(
          find.descendant(
            of: find.byElementPredicate((e) => e == element),
            matching: find.byType(Text),
          ),
        )
        .map((t) => t.data ?? '')
        .where((t) => t.isNotEmpty);
    if (texts.isNotEmpty) labels.add(texts.first);
  }
  return labels;
}

/// Uses whatever profile-editing UI the real Profile screen offers to set
/// the full name to [newFullName]. Reports what was found and shown; it
/// never decides whether the update succeeded.
Future<ProfileEditAttempt> attemptProfileEdit(
  WidgetTester tester, {
  required String newFullName,
}) async {
  // Make every lazily built entry of the Profile ListView exist.
  final scrollable = find
      .descendant(of: profileScreen, matching: find.byType(Scrollable))
      .first;
  final position = tester.state<ScrollableState>(scrollable).position;
  final actions = <String>{};
  for (var i = 0; i < 20; i++) {
    actions.addAll(_actionLabels(tester, profileScreen));
    if (position.pixels >= position.maxScrollExtent) break;
    position.jumpTo(
      (position.pixels + 250).clamp(0, position.maxScrollExtent).toDouble(),
    );
    await tester.pump();
  }
  position.jumpTo(0);
  await tester.pump();

  // 1. Editable fields directly on the Profile screen?
  var formScope = profileScreen;
  var fields = find.descendant(
    of: formScope,
    matching: find.byType(EditableText),
  );
  String? editEntry;

  // 2. Otherwise an "Edit profile"-type entry that opens a form?
  if (fields.evaluate().isEmpty) {
    for (final label in actions) {
      if (_editEntryPattern.hasMatch(label)) {
        editEntry = label;
        break;
      }
    }
    if (editEntry != null) {
      final entry = find.text(editEntry);
      await scrollUntilBuilt(tester, entry, screen: app.ProfileScreen);
      await tapVisible(tester, entry);
      await pumpFor(tester, const Duration(milliseconds: 600));
      formScope = find.byType(Scaffold).last;
      fields = find.descendant(
        of: formScope,
        matching: find.byType(EditableText),
      );
    }
  }

  final fieldCount = fields.evaluate().length;
  String? saveAction;
  if (fieldCount > 0) {
    await tester.enterText(fields.first, newFullName);
    await tester.pump();
    for (final label in _actionLabels(tester, formScope)) {
      if (_saveActionPattern.hasMatch(label)) {
        saveAction = label;
        break;
      }
    }
    if (saveAction != null) {
      final save = find.descendant(
        of: formScope,
        matching: find.text(saveAction),
      );
      await tester.ensureVisible(save.first);
      await tester.tap(save.first);
      await pumpFor(tester, const Duration(milliseconds: 800));
    }
  }

  final fieldErrors = tester
      .widgetList<InputDecorator>(find.byType(InputDecorator))
      .map((d) => d.decoration.errorText)
      .whereType<String>()
      .where((t) => t.isNotEmpty)
      .toList();

  return ProfileEditAttempt(
    profileActions: actions.toList(),
    editEntry: editEntry,
    editableFieldCount: fieldCount,
    saveAction: saveAction,
    messages: shownSnackBarTexts(tester),
    fieldErrors: fieldErrors,
  );
}

/// Texts of every SnackBar currently shown (any screen).
List<String> shownSnackBarTexts(WidgetTester tester) => tester
    .widgetList<Text>(
      find.descendant(of: find.byType(SnackBar), matching: find.byType(Text)),
    )
    .map((t) => t.data ?? '')
    .where((t) => t.isNotEmpty)
    .toList();
