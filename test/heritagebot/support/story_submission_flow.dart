// HERITAGEBOT - TEST SUPPORT: drives the real story-submission screens for
// CASE-048..CASE-050 (Community Contributor Management / Submit Heritage
// Story). It only taps and types; results are read by each test.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:heritagebot/main.dart' as app;

import 'heritagebot_fixtures.dart';

/// Signed-in contributor: AuthGate -> MainShell(contributor) -> "Contribute"
/// tab -> ContributorDashboardScreen -> "Submit Story" ->
/// SubmitCommunityStoryScreen (contributor profile loaded).
Future<void> openSubmitStoryScreen(WidgetTester tester) async {
  await launchAuthGate(tester, until: app.MainShell);
  await tapNavDestination(tester, 'Contribute');
  await pumpUntilFound(tester, find.byType(app.ContributorDashboardScreen));
  await pumpFor(tester, const Duration(milliseconds: 300));
  await tapVisible(tester, find.text('Submit Story'));
  await pumpUntilFound(tester, find.byType(app.SubmitCommunityStoryScreen));
  await pumpFor(tester, const Duration(milliseconds: 600));
}

/// Types [title] and [story] into the real form and taps "Submit for Review".
Future<void> fillAndSubmitStory(
  WidgetTester tester, {
  required String title,
  required String story,
}) async {
  final fields = fieldsOf(app.SubmitCommunityStoryScreen);
  expect(fields, findsNWidgets(2), reason: 'Story Title + Heritage Story');
  await tester.enterText(fields.at(0), title);
  await tester.pump();
  await tester.enterText(fields.at(1), story);
  await tester.pump();

  final submit = find.text('Submit for Review');
  await scrollUntilBuilt(tester, submit,
      screen: app.SubmitCommunityStoryScreen);
  await tapVisible(tester, submit);
  await pumpFor(tester, const Duration(milliseconds: 800));
}

/// Texts of every SnackBar currently shown.
List<String> snackBarTexts(WidgetTester tester) =>
    textsUnder(tester, find.byType(SnackBar));
