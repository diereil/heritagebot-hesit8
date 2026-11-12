// TEST ADAPTER REQUIRED FOR HERITAGEBOT'S REAL IMPLEMENTATION.
// Without access to your lib/ project, it is unsafe to invent Flutter screen
// names, Firebase methods, Firestore schemas, GPS plugin behaviors, or AI APIs.
// Every generated test is SKIPPED until createHeritageBotTestAdapter() returns
// an implementation that actually calls your application's functions.
//
// Example observed fields (CASE-001):
// { 'loginAccepted': false, 'emailErrorVisible': true }
// These fields must be DERIVED from actual validator or widget state, NOT
// copied from a test's expected values. Returning canned results is not a test.

class HeritageBotScenario {
  final String id;
  final String kind;
  final String module;
  final String unit;
  final String proponent;
  final String description;
  final String expectedResult;
  final String? precondition;
  final Map<String, Object?> inputs;

  const HeritageBotScenario({
    required this.id,
    required this.kind,
    required this.module,
    required this.unit,
    required this.proponent,
    required this.description,
    required this.expectedResult,
    this.precondition,
    this.inputs = const <String, Object?>{},
  });
}

abstract class HeritageBotTestAdapter {
  /// Run the scenario against your real HeritageBot implementation.
  /// Provide observations such as real UI state, service response or database
  /// state. Do not return a hardcoded "passed" flag.
  Future<Map<String, Object?>> execute(HeritageBotScenario scenario);
}

/// TODO: Replace null with a real adapter instance after connecting your lib/.
/// Until then, tests show "SKIPPED", not "PASSED" or a fabricated outcome.
HeritageBotTestAdapter? createHeritageBotTestAdapter() {
  return null;
}
