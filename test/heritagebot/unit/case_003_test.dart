
import 'package:flutter_test/flutter_test.dart';
import 'package:heritagebot/utils/password_validator.dart';

// HERITAGEBOT - UNIT TESTING
// Test Case ID: CASE-003
// Proponent: Reil Esdrelon
// Module: Authenticate User
// Unit: Login
// Test Description: Password field left blank
// Expected Result: Require a password

void main() {
  group('HERITAGEBOT - Authentication Module', () {
    test('CASE-003 - Password Field Left Blank', () {
      // Step 1: Prepare an empty password input.
      const String password = '';

      // Step 2: Execute the password validator.
      final String? actualResult = validatePassword(password);

      // Step 3: Define the expected result.
      const String expectedResult = 'Password is required';

      // Step 4: Verify that an empty password is rejected.
      expect(
        actualResult,
        isNotNull,
        reason: 'CASE-003: Empty password must be rejected.',
      );

      // Step 5: Verify the correct validation message.
      expect(
        actualResult,
        equals(expectedResult),
        reason: 'CASE-003: Incorrect password validation message.',
      );
    });
  });
}
