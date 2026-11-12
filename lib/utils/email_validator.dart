
String? validateEmail(String? email) {
  if (email == null || email.trim().isEmpty) {
    return 'Email is required';
  }

  final emailRegex =
      RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

  if (!emailRegex.hasMatch(email.trim())) {
    return 'Invalid email format';
  }

  return null;
}
