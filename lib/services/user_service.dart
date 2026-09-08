import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../models/user_profile.dart';

class UserService {
  static const Set<String> adminEmails = {
    'banalads@gmail.com',
    'phoebekitzssultan@gmail.com',
  };

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  DocumentReference<Map<String, dynamic>> _userDocument(String uid) {
    return _firestore.collection('users').doc(uid);
  }

  bool isAuthorizedAdmin(User user) {
    final email = user.email?.trim().toLowerCase() ?? '';
    return adminEmails.contains(email);
  }

  Future<UserProfile?> getUserProfile(String uid) async {
    final currentUser = FirebaseAuth.instance.currentUser;

    if (currentUser != null &&
        currentUser.uid == uid &&
        isAuthorizedAdmin(currentUser)) {
      return _createOrUpdateAdminProfile(currentUser);
    }

    final snapshot = await _userDocument(uid).get();

    if (!snapshot.exists) {
      return null;
    }

    final data = snapshot.data();

    if (data == null) {
      return null;
    }

    return UserProfile.fromMap(data, uid: uid);
  }

  Future<UserProfile> _createOrUpdateAdminProfile(User firebaseUser) async {
    final reference = _userDocument(firebaseUser.uid);
    final existing = await reference.get();
    final existingData = existing.data();

    final now = DateTime.now().millisecondsSinceEpoch;

    final fullName = firebaseUser.displayName?.trim().isNotEmpty == true
        ? firebaseUser.displayName!.trim()
        : (existingData?['fullName']?.toString().trim().isNotEmpty == true
              ? existingData!['fullName'].toString().trim()
              : 'HeritageBot Administrator');

    final preferredLanguage =
        existingData?['preferredLanguage']?.toString().trim().isNotEmpty == true
        ? existingData!['preferredLanguage'].toString().trim()
        : 'en';

    final createdAtMillisRaw = existingData?['createdAtMillis'];

    final int createdAtMillis = createdAtMillisRaw is int
        ? createdAtMillisRaw
        : createdAtMillisRaw is num
        ? createdAtMillisRaw.toInt()
        : now;

    final data = <String, dynamic>{
      'uid': firebaseUser.uid,
      'fullName': fullName,
      'email': firebaseUser.email?.trim() ?? '',
      'role': UserRoles.admin,
      'preferredLanguage': preferredLanguage,
      'accountStatus': 'active',
      'photoUrl': firebaseUser.photoURL?.trim() ?? '',
      'createdAtMillis': createdAtMillis,
      'updatedAtMillis': now,
    };

    await reference.set(data, SetOptions(merge: true));

    return UserProfile.fromMap(data, uid: firebaseUser.uid);
  }

  Future<void> savePublicProfile({
    required User firebaseUser,
    required String fullName,
    required String role,
    required String preferredLanguage,
  }) async {
    if (isAuthorizedAdmin(firebaseUser)) {
      await _createOrUpdateAdminProfile(firebaseUser);
      return;
    }

    if (!UserRoles.isPublicRole(role)) {
      throw ArgumentError(
        'Public registration can only create Tourist or Community Contributor accounts.',
      );
    }

    final reference = _userDocument(firebaseUser.uid);
    final existing = await reference.get();

    if (existing.exists) {
      final existingData = existing.data();
      final existingRole = existingData?['role']?.toString() ?? '';

      if (UserRoles.isValidRole(existingRole)) {
        return;
      }
    }

    final safeName = fullName.trim().isNotEmpty
        ? fullName.trim()
        : (firebaseUser.displayName?.trim().isNotEmpty == true
              ? firebaseUser.displayName!.trim()
              : 'HeritageBot User');

    final now = DateTime.now().millisecondsSinceEpoch;

    await reference.set({
      'uid': firebaseUser.uid,
      'fullName': safeName,
      'email': firebaseUser.email?.trim() ?? '',
      'role': role,
      'preferredLanguage': preferredLanguage.trim().isEmpty
          ? 'en'
          : preferredLanguage.trim(),
      'accountStatus': 'active',
      'photoUrl': firebaseUser.photoURL?.trim() ?? '',
      'createdAtMillis': now,
      'updatedAtMillis': now,
    }, SetOptions(merge: true));
  }

  Future<void> updatePreferredLanguage(String code) async {
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      return;
    }

    await _userDocument(user.uid).set({
      'preferredLanguage': code,
      'updatedAtMillis': DateTime.now().millisecondsSinceEpoch,
    }, SetOptions(merge: true));
  }
}
