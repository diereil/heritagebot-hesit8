import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_facebook_auth/flutter_facebook_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;

  Stream<User?> authChanges() {
    return _auth.authStateChanges();
  }

  bool isPasswordUser(User user) {
    return user.providerData.any((info) => info.providerId == 'password');
  }

  bool needsEmailVerification(User user) {
    return isPasswordUser(user) && !user.emailVerified;
  }

  Future<void> loginWithEmail(String email, String password) async {
    await _auth.signInWithEmailAndPassword(
      email: email.trim(),
      password: password,
    );
  }

  Future<UserCredential> signupWithEmail(
    String email,
    String password, {
    String? displayName,
  }) async {
    final credential = await _auth.createUserWithEmailAndPassword(
      email: email.trim(),
      password: password,
    );

    final user = credential.user;

    if (user != null) {
      final safeName = displayName?.trim() ?? '';

      if (safeName.isNotEmpty) {
        await user.updateDisplayName(safeName);
      }

      await user.sendEmailVerification();
    }

    return credential;
  }

  Future<void> sendPasswordResetEmail(String email) async {
    final trimmedEmail = email.trim();

    if (trimmedEmail.isEmpty) {
      throw FirebaseAuthException(
        code: 'empty-email',
        message: 'Please enter your email address first.',
      );
    }

    await _auth.sendPasswordResetEmail(email: trimmedEmail);
  }

  Future<void> changeCurrentUserPassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    final user = _auth.currentUser;

    if (user == null) {
      throw FirebaseAuthException(
        code: 'no-current-user',
        message: 'No user is currently signed in.',
      );
    }

    if (!isPasswordUser(user)) {
      throw FirebaseAuthException(
        code: 'not-password-user',
        message:
            'Password change is only available for email/password accounts. Google and Facebook accounts must change their password from their provider.',
      );
    }

    final email = user.email;

    if (email == null || email.trim().isEmpty) {
      throw FirebaseAuthException(
        code: 'missing-email',
        message: 'This account has no email address.',
      );
    }

    if (currentPassword.trim().isEmpty) {
      throw FirebaseAuthException(
        code: 'empty-current-password',
        message: 'Please enter your current password.',
      );
    }

    if (newPassword.trim().length < 6) {
      throw FirebaseAuthException(
        code: 'weak-password',
        message: 'New password must be at least 6 characters.',
      );
    }

    final credential = EmailAuthProvider.credential(
      email: email.trim(),
      password: currentPassword,
    );

    await user.reauthenticateWithCredential(credential);

    await user.updatePassword(newPassword.trim());
  }

  Future<void> resendEmailVerification() async {
    final user = _auth.currentUser;

    if (user == null) {
      throw Exception('No user is currently signed in.');
    }

    await user.sendEmailVerification();
  }

  Future<bool> reloadAndCheckVerified() async {
    final user = _auth.currentUser;

    if (user == null) {
      return false;
    }

    await user.reload();

    final refreshedUser = _auth.currentUser;

    return refreshedUser?.emailVerified ?? false;
  }

  Future<void> signInWithGoogle() async {
    try {
      await GoogleSignIn.instance.signOut();

      final GoogleSignInAccount googleUser = await GoogleSignIn.instance
          .authenticate();

      final GoogleSignInAuthentication googleAuth = googleUser.authentication;

      if (googleAuth.idToken == null) {
        throw Exception(
          'Google login failed because no ID token was returned. Please check SHA-1/SHA-256 and google-services.json.',
        );
      }

      final OAuthCredential credential = GoogleAuthProvider.credential(
        idToken: googleAuth.idToken,
      );

      await _auth.signInWithCredential(credential);
    } catch (e) {
      throw Exception('Google login error: $e');
    }
  }

  Future<void> signInWithFacebook() async {
    final LoginResult result = await FacebookAuth.instance.login(
      permissions: ['email', 'public_profile'],
    );

    if (result.status != LoginStatus.success || result.accessToken == null) {
      throw Exception('Facebook login was cancelled or failed.');
    }

    final String token = result.accessToken!.tokenString;

    final OAuthCredential credential = FacebookAuthProvider.credential(token);

    await _auth.signInWithCredential(credential);
  }

  Future<void> logout() async {
    await GoogleSignIn.instance.signOut();
    await FacebookAuth.instance.logOut();
    await _auth.signOut();
  }
}
