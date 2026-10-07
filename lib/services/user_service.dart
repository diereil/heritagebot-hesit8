import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../models/user_profile.dart';

class UserService {
  static const Set<String> adminEmails = {
    'banalads@gmail.com',
    'phoebekitzssultan@gmail.com',
    'shawnmorales39@gmail.com',
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

    return UserProfile.fromMap(
      data,
      uid: uid,
    );
  }

  Future<UserProfile> _createOrUpdateAdminProfile(User firebaseUser) async {
    final reference = _userDocument(firebaseUser.uid);
    final existing = await reference.get();
    final existingData = existing.data();

    final now = DateTime.now().millisecondsSinceEpoch;

    final fullName =
        firebaseUser.displayName?.trim().isNotEmpty == true
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

    await reference.set(
      data,
      SetOptions(merge: true),
    );

    return UserProfile.fromMap(
      data,
      uid: firebaseUser.uid,
    );
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

    await reference.set(
      {
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
      },
      SetOptions(merge: true),
    );
  }

  Future<void> updatePreferredLanguage(String code) async {
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      return;
    }

    await _userDocument(user.uid).set(
      {
        'preferredLanguage': code,
        'updatedAtMillis': DateTime.now().millisecondsSinceEpoch,
      },
      SetOptions(merge: true),
    );
  }


  bool isAuthorizedAdminEmail(String email) {
    return adminEmails.contains(email.trim().toLowerCase());
  }

  Future<List<UserProfile>> getAllUsers() async {
    final snapshot = await _firestore.collection('users').get();

    final users = snapshot.docs
        .map(
          (doc) => UserProfile.fromMap(
            doc.data(),
            uid: doc.id,
          ),
        )
        .toList();

    users.sort((a, b) {
      final aAdmin = a.isAdmin ? 0 : 1;
      final bAdmin = b.isAdmin ? 0 : 1;

      if (aAdmin != bAdmin) {
        return aAdmin.compareTo(bAdmin);
      }

      return a.fullName.toLowerCase().compareTo(
            b.fullName.toLowerCase(),
          );
    });

    return users;
  }

  Future<void> updateAccountStatus({
    required UserProfile profile,
    required String status,
  }) async {
    final safeStatus = status.trim().toLowerCase();

    if (safeStatus != 'active' && safeStatus != 'suspended') {
      throw ArgumentError(
        'Account status must be active or suspended.',
      );
    }

    if (profile.isAdmin ||
        isAuthorizedAdminEmail(profile.email)) {
      throw StateError(
        'Administrator accounts cannot be suspended from this screen.',
      );
    }

    await _userDocument(profile.uid).update({
      'accountStatus': safeStatus,
      'updatedAtMillis': DateTime.now().millisecondsSinceEpoch,
    });
  }

}