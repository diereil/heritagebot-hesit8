
String? validatePassword(String? password) {
  if (password == null || password.trim().isEmpty) {
    return 'Password is required';
  }

  return null;
}
