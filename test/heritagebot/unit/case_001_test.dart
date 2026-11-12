
import 'package:flutter_test/flutter_test.dart';
import 'package:heritagebot/utils/email_validator.dart';

// HERITAGEBOT - UNIT TESTING
// Test Case ID: CASE-001
// Proponent: Reil Esdrelon
// Module: Authenticate User
// Unit: Login
// Test Description: Invalid email format
// Expected Result: Display email validation error

void main() {
  group('HERITAGEBOT - Authentication Module', () {
    test('CASE-001 - Invalid Email Format', () {
      // Step 1: Prepare invalid email input.
      const String email = 'not-an-email';

      // Step 2: Execute the actual validator.
      final String? actualResult = validateEmail(email);

      // Step 3: Define expected result.
      const String expectedResult = 'Invalid email format';

      // Step 4: Verify invalid email is rejected.
      expect(
        actualResult,
        isNotNull,
        reason: 'Invalid email must be rejected.',
      );

      // Step 5: Verify the exact error message.
      expect(
        actualResult,
        equals(expectedResult),
        reason: 'The validator must return the correct error.',
      );
    });
  });
}
