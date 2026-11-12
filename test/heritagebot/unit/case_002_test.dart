
import 'package:flutter_test/flutter_test.dart';
import 'package:heritagebot/utils/email_validator.dart';

// HERITAGEBOT - UNIT TESTING
// Test Case ID: CASE-002
// Proponent: Reil Esdrelon
// Module: Authenticate User
// Unit: Login
// Test Description: Email field left blank
// Expected Result: Require an email address

void main() {
  group('HERITAGEBOT - Authentication Module', () {
    test('CASE-002 - Email Field Left Blank', () {
      // Step 1: Prepare an empty email input.
      const String email = '';

      // Step 2: Execute the email validator.
      final String? actualResult = validateEmail(email);

      // Step 3: Define the expected result.
      const String expectedResult = 'Email is required';

      // Step 4: Verify that an empty email is rejected.
      expect(
        actualResult,
        isNotNull,
        reason: 'CASE-002: Empty email must be rejected.',
      );

      // Step 5: Verify the correct validation message.
      expect(
        actualResult,
        equals(expectedResult),
        reason: 'CASE-002: Incorrect email validation message.',
      );
    });
  });
}
