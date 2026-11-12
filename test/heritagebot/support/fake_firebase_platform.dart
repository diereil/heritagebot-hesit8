// HERITAGEBOT - TEST SUPPORT: In-memory Firebase platform fakes.
//
// PURPOSE
// HeritageBot's AuthService and UserService use FirebaseAuth.instance and
// FirebaseFirestore.instance directly. To widget-test the REAL login screen,
// AuthGate, UserService and MainShell without a device, emulator or live
// Firebase project, this file replaces only the lowest Firebase layer: the
// native *platform* implementation that FlutterFire is designed to let tests
// swap out (FirebaseAuthPlatform.instance / FirebaseFirestorePlatform.instance).
//
// Everything above this layer is unmodified production code:
//   LoginSignupScreen -> AuthService -> FirebaseAuth (real package API)
//   AuthGate -> UserService -> FirebaseFirestore (real package API)
//
// These fakes do NOT decide whether a test passes. They only:
//   * accept a sign-in when the email/password match a seeded account
//     (and reject it otherwise, like Firebase does),
//   * record every auth call (sign-in, sign-up, reset, verification,
//     re-authentication, password update) so tests can verify what the app sent,
//   * store and return Firestore documents seeded by the test.
//
// No file in lib/ is modified by this support code.

// These are transitive dependencies of firebase_core / firebase_auth /
// cloud_firestore (already in pubspec.lock); pubspec.yaml is not modified.
// ignore_for_file: depend_on_referenced_packages, invalid_use_of_protected_member

import 'dart:async';

import 'package:cloud_firestore_platform_interface/cloud_firestore_platform_interface.dart';
import 'package:firebase_auth_platform_interface/firebase_auth_platform_interface.dart';
import 'package:firebase_core/firebase_core.dart';

// ---------------------------------------------------------------------------
// FIREBASE AUTH
// ---------------------------------------------------------------------------
//
// Extended for CASE-007..CASE-030 (additive only - the API used by
// CASE-004..006 is unchanged): account creation, password reset requests,
// e-mail verification links (applyActionCode), re-authentication, password
// update, display-name update and Google (OAuth) credential sign-in.
// Every operation follows the documented Firebase Authentication contract
// (same error codes) and is RECORDED so tests can verify what the real app
// actually sent. The fake never decides whether a test passes.

/// A seeded Firebase Authentication account.
class FakeAuthAccount {
  final String uid;
  final String email;
  final String password;
  final String? displayName;
  final bool emailVerified;

  /// 'password' (email/password provider) or e.g. 'google.com'.
  final String providerId;

  const FakeAuthAccount({
    required this.uid,
    required this.email,
    required this.password,
    this.displayName,
    this.emailVerified = true,
    this.providerId = 'password',
  });
}

/// Record of a call the application made to signInWithEmailAndPassword.
class FakeSignInCall {
  final String email;
  final String password;

  const FakeSignInCall(this.email, this.password);

  @override
  String toString() => 'FakeSignInCall(email: $email)';
}

/// An e-mail verification link issued by sendEmailVerification().
class FakeVerificationLink {
  FakeVerificationLink({
    required this.oobCode,
    required this.email,
    required this.expiresAt,
  });

  final String oobCode;
  final String email;
  DateTime expiresAt;
  bool used = false;

  bool get isExpired => DateTime.now().isAfter(expiresAt);
}

/// Mutable server-side state of one auth account.
class _StoredAccount {
  _StoredAccount({
    required this.uid,
    required this.email,
    required this.password,
    required this.displayName,
    required this.emailVerified,
    required this.providerId,
  });

  factory _StoredAccount.from(FakeAuthAccount a) => _StoredAccount(
        uid: a.uid,
        email: a.email,
        password: a.password,
        displayName: a.displayName,
        emailVerified: a.emailVerified,
        providerId: a.providerId,
      );

  final String uid;
  final String email;
  String password;
  String? displayName;
  bool emailVerified;
  final String providerId;
}

class FakeFirebaseAuthPlatform extends FirebaseAuthPlatform {
  FakeFirebaseAuthPlatform({List<FakeAuthAccount> accounts = const []})
      : _accounts = accounts.map(_StoredAccount.from).toList(),
        super();

  final List<_StoredAccount> _accounts;
  final List<FakeSignInCall> signInCalls = <FakeSignInCall>[];

  /// E-mails passed to createUserWithEmailAndPassword (attempts, incl. rejected).
  final List<String> createUserCalls = <String>[];

  /// E-mails passed to sendPasswordResetEmail.
  final List<String> passwordResetRequests = <String>[];

  /// Verification links "e-mailed" by sendEmailVerification.
  final List<FakeVerificationLink> verificationLinks = <FakeVerificationLink>[];

  /// Provider ids of credentials passed to signInWithCredential.
  final List<String> credentialSignInCalls = <String>[];

  /// Re-authentication attempts (email) and password updates (uid).
  final List<String> reauthenticationCalls = <String>[];
  final List<String> passwordUpdates = <String>[];

  /// Google ID token -> uid, i.e. which Google identity maps to which
  /// Firebase account (Firebase does this server side).
  final Map<String, String> _oauthIdTokens = <String, String>{};

  int _uidCounter = 0;
  int _oobCounter = 0;

  final StreamController<UserPlatform?> _authEvents =
      StreamController<UserPlatform?>.broadcast();

  UserPlatform? _currentUser;

  // ----- test inspection / setup helpers ---------------------------------

  /// Returns a snapshot of the stored account, or null when none exists.
  FakeAuthAccount? accountByEmail(String email) {
    final stored = _find(email);
    if (stored == null) return null;
    return FakeAuthAccount(
      uid: stored.uid,
      email: stored.email,
      password: stored.password,
      displayName: stored.displayName,
      emailVerified: stored.emailVerified,
      providerId: stored.providerId,
    );
  }

  int get accountCount => _accounts.length;

  /// Registers the Firebase account that a Google ID token resolves to.
  void registerOAuthIdToken(String idToken, String uid) {
    _oauthIdTokens[idToken] = uid;
  }

  /// Makes every outstanding verification link older than its lifetime.
  void expireAllVerificationLinks() {
    for (final link in verificationLinks) {
      link.expiresAt = DateTime.now().subtract(const Duration(minutes: 1));
    }
  }

  void clearCallLogs() {
    signInCalls.clear();
    createUserCalls.clear();
    passwordResetRequests.clear();
    verificationLinks.clear();
    credentialSignInCalls.clear();
    reauthenticationCalls.clear();
    passwordUpdates.clear();
  }

  _StoredAccount? _find(String email) {
    for (final account in _accounts) {
      if (account.email.toLowerCase() == email.trim().toLowerCase()) {
        return account;
      }
    }
    return null;
  }

  void _signIn(_StoredAccount account) {
    final user = FakeUserPlatform(this, account);
    _currentUser = user;
    _authEvents.add(user);
  }

  /// Rebuilds the current user's snapshot (like the SDK after reload()).
  void _refreshCurrentUser(_StoredAccount account) {
    if (_currentUser?.uid == account.uid) {
      _currentUser = FakeUserPlatform(this, account);
    }
  }

  FakeVerificationLink _issueVerificationLink(_StoredAccount account) {
    final link = FakeVerificationLink(
      oobCode: 'fake-oob-code-${_oobCounter++}',
      email: account.email,
      // Firebase e-mail action links are short-lived.
      expiresAt: DateTime.now().add(const Duration(hours: 1)),
    );
    verificationLinks.add(link);
    return link;
  }

  // ----- FirebaseAuthPlatform ---------------------------------------------

  @override
  FirebaseAuthPlatform delegateFor({required FirebaseApp app}) => this;

  @override
  FirebaseAuthPlatform setInitialValues({
    InternalUserDetails? currentUser,
    String? languageCode,
  }) =>
      this;

  @override
  UserPlatform? get currentUser => _currentUser;

  @override
  set currentUser(UserPlatform? userPlatform) {
    _currentUser = userPlatform;
  }

  @override
  String? get languageCode => null;

  /// Like the native SDK: emits the current state on listen, then changes.
  Stream<UserPlatform?> _stateStream() async* {
    yield _currentUser;
    yield* _authEvents.stream;
  }

  @override
  Stream<UserPlatform?> authStateChanges() => _stateStream();

  @override
  Stream<UserPlatform?> idTokenChanges() => _stateStream();

  @override
  Stream<UserPlatform?> userChanges() => _stateStream();

  @override
  Future<UserCredentialPlatform> signInWithEmailAndPassword(
    String email,
    String password,
  ) async {
    signInCalls.add(FakeSignInCall(email, password));

    final match = _find(email);

    if (match == null ||
        match.providerId != 'password' ||
        match.password != password) {
      throw FirebaseAuthException(
        code: 'invalid-credential',
        message: 'The supplied auth credential is incorrect.',
      );
    }

    _signIn(match);
    return FakeUserCredentialPlatform(auth: this, user: _currentUser);
  }

  @override
  Future<UserCredentialPlatform> createUserWithEmailAndPassword(
    String email,
    String password,
  ) async {
    createUserCalls.add(email);

    if (_find(email) != null) {
      throw FirebaseAuthException(
        code: 'email-already-in-use',
        message: 'The email address is already in use by another account.',
      );
    }

    if (password.length < 6) {
      throw FirebaseAuthException(
        code: 'weak-password',
        message: 'Password should be at least 6 characters',
      );
    }

    final account = _StoredAccount(
      uid: 'fake-created-uid-${_uidCounter++}',
      email: email.trim(),
      password: password,
      displayName: null,
      emailVerified: false,
      providerId: 'password',
    );
    _accounts.add(account);

    // Firebase signs the new user in immediately.
    _signIn(account);
    return FakeUserCredentialPlatform(auth: this, user: _currentUser);
  }

  @override
  Future<UserCredentialPlatform> signInWithCredential(
    AuthCredential credential,
  ) async {
    credentialSignInCalls.add(credential.providerId);

    String? uid;
    if (credential is OAuthCredential && credential.idToken != null) {
      uid = _oauthIdTokens[credential.idToken!];
    }

    _StoredAccount? match;
    for (final account in _accounts) {
      if (account.uid == uid && account.providerId == credential.providerId) {
        match = account;
      }
    }

    if (match == null) {
      throw FirebaseAuthException(
        code: 'invalid-credential',
        message: 'The supplied auth credential is malformed or has expired.',
      );
    }

    _signIn(match);
    return FakeUserCredentialPlatform(auth: this, user: _currentUser);
  }

  @override
  Future<void> sendPasswordResetEmail(
    String email, [
    ActionCodeSettings? actionCodeSettings,
  ]) async {
    passwordResetRequests.add(email);

    if (_find(email) == null) {
      throw FirebaseAuthException(
        code: 'user-not-found',
        message: 'There is no user record corresponding to this identifier.',
      );
    }
  }

  /// What Firebase's hosted action page does when the user opens the link
  /// from their inbox.
  @override
  Future<void> applyActionCode(String code) async {
    FakeVerificationLink? link;
    for (final candidate in verificationLinks) {
      if (candidate.oobCode == code) link = candidate;
    }

    if (link == null || link.used) {
      throw FirebaseAuthException(
        code: 'invalid-action-code',
        message: 'The action code is invalid. This can happen if the code '
            'is malformed, expired, or has already been used.',
      );
    }

    if (link.isExpired) {
      throw FirebaseAuthException(
        code: 'expired-action-code',
        message: 'The action code has expired.',
      );
    }

    link.used = true;
    _find(link.email)!.emailVerified = true;
  }

  @override
  Future<void> signOut() async {
    _currentUser = null;
    _authEvents.add(null);
  }

  @override
  Future<void> dispose() async {}
}

class _FakeMultiFactorPlatform extends MultiFactorPlatform {
  _FakeMultiFactorPlatform(super.auth);
}

class FakeUserPlatform extends UserPlatform {
  FakeUserPlatform(this._fakeAuth, this._account)
      : super(
          _fakeAuth,
          _FakeMultiFactorPlatform(_fakeAuth),
          _details(_account),
        );

  final FakeFirebaseAuthPlatform _fakeAuth;
  final _StoredAccount _account;

  static InternalUserDetails _details(_StoredAccount account) {
    return InternalUserDetails(
      userInfo: InternalUserInfo(
        uid: account.uid,
        email: account.email,
        displayName: account.displayName,
        isAnonymous: false,
        isEmailVerified: account.emailVerified,
        providerId: 'firebase',
      ),
      providerData: <Map<Object?, Object?>?>[
        <Object?, Object?>{
          'uid': account.email,
          'email': account.email,
          'displayName': account.displayName,
          'providerId': account.providerId,
          'isAnonymous': false,
          'isEmailVerified': account.emailVerified,
        },
      ],
    );
  }

  @override
  Future<void> reload() async {
    _fakeAuth._refreshCurrentUser(_account);
  }

  @override
  Future<String?> getIdToken(bool forceRefresh) async => 'fake-id-token';

  @override
  Future<void> sendEmailVerification(
    ActionCodeSettings? actionCodeSettings,
  ) async {
    _fakeAuth._issueVerificationLink(_account);
  }

  @override
  Future<void> updateProfile(Map<String, String?> profile) async {
    if (profile.containsKey('displayName')) {
      _account.displayName = profile['displayName'];
    }
    _fakeAuth._refreshCurrentUser(_account);
  }

  @override
  Future<UserCredentialPlatform> reauthenticateWithCredential(
    AuthCredential credential,
  ) async {
    _fakeAuth.reauthenticationCalls.add(_account.email);

    if (credential is! EmailAuthCredential ||
        credential.email.toLowerCase() != _account.email.toLowerCase() ||
        credential.password != _account.password) {
      throw FirebaseAuthException(
        code: 'invalid-credential',
        message: 'The supplied auth credential is incorrect.',
      );
    }

    return FakeUserCredentialPlatform(auth: _fakeAuth, user: this);
  }

  @override
  Future<void> updatePassword(String newPassword) async {
    if (newPassword.length < 6) {
      throw FirebaseAuthException(
        code: 'weak-password',
        message: 'Password should be at least 6 characters',
      );
    }
    _account.password = newPassword;
    _fakeAuth.passwordUpdates.add(_account.uid);
  }
}

class FakeUserCredentialPlatform extends UserCredentialPlatform {
  FakeUserCredentialPlatform({required super.auth, super.user});
}

// ---------------------------------------------------------------------------
// CLOUD FIRESTORE
// ---------------------------------------------------------------------------

final Map<String, dynamic> _defaultQueryParameters = <String, dynamic>{
  'where': <List<dynamic>>[],
  'orderBy': <List<dynamic>>[],
  'startAt': null,
  'startAfter': null,
  'endAt': null,
  'endBefore': null,
  'limit': null,
  'limitToLast': null,
};

InternalSnapshotMetadata _metadata() =>
    InternalSnapshotMetadata(hasPendingWrites: false, isFromCache: false);

String _parentPath(String documentPath) {
  final index = documentPath.lastIndexOf('/');
  return index < 0 ? '' : documentPath.substring(0, index);
}

class FakeFirebaseFirestorePlatform extends FirebaseFirestorePlatform {
  FakeFirebaseFirestorePlatform() : super();

  /// In-memory documents keyed by full document path (e.g. "users/uid").
  final Map<String, Map<String, dynamic>> documents =
      <String, Map<String, dynamic>>{};

  int _autoId = 0;

  String nextAutoId() => 'fake_doc_${_autoId++}';

  void seedDocument(String path, Map<String, dynamic> data) {
    documents[path] = Map<String, dynamic>.of(data);
  }

  @override
  FirebaseFirestorePlatform delegateFor({
    required FirebaseApp app,
    required String databaseId,
  }) =>
      this;

  @override
  CollectionReferencePlatform collection(String collectionPath) =>
      FakeCollectionReferencePlatform(this, collectionPath);

  @override
  DocumentReferencePlatform doc(String documentPath) =>
      FakeDocumentReferencePlatform(this, documentPath);

  /// Collection-group query: matches every document whose immediate parent
  /// collection id equals [collectionPath] (e.g. users/{uid}/bookmarks/{id}).
  /// Needed by the real AdminAnalyticsService on the admin Summary dashboard.
  @override
  QueryPlatform collectionGroup(String collectionPath) => FakeQueryPlatform(
        this,
        collectionPath,
        Map<String, dynamic>.of(_defaultQueryParameters),
        isCollectionGroup: true,
      );
}

class FakeDocumentReferencePlatform extends DocumentReferencePlatform {
  FakeDocumentReferencePlatform(this._store, String path) : super(_store, path);

  final FakeFirebaseFirestorePlatform _store;

  DocumentSnapshotPlatform _snapshot() {
    final data = _store.documents[path];
    return DocumentSnapshotPlatform(
      _store,
      path,
      data == null ? null : Map<String?, Object?>.of(data),
      _metadata(),
    );
  }

  @override
  Future<DocumentSnapshotPlatform> get([
    GetOptions options = const GetOptions(),
  ]) async =>
      _snapshot();

  @override
  Stream<DocumentSnapshotPlatform> snapshots({
    bool includeMetadataChanges = false,
    required ListenSource listenSource,
  }) =>
      Stream<DocumentSnapshotPlatform>.value(_snapshot());

  @override
  Future<void> set(Map<String, dynamic> data, [SetOptions? options]) async {
    final merge = options?.merge == true;
    final existing = _store.documents[path];
    _store.documents[path] = merge && existing != null
        ? (Map<String, dynamic>.of(existing)..addAll(data))
        : Map<String, dynamic>.of(data);
  }

  @override
  Future<void> update(Map<FieldPath, dynamic> data) async {
    final existing = _store.documents[path];
    if (existing == null) {
      throw FirebaseException(plugin: 'cloud_firestore', code: 'not-found');
    }
    for (final entry in data.entries) {
      existing[entry.key.components.join('.')] = entry.value;
    }
  }

  @override
  Future<void> delete() async {
    _store.documents.remove(path);
  }
}

class FakeQueryPlatform extends QueryPlatform {
  FakeQueryPlatform(
    this._store,
    this.collectionPath,
    Map<String, dynamic> params, {
    this.isCollectionGroup = false,
  }) : super(_store, params);

  final FakeFirebaseFirestorePlatform _store;
  final String collectionPath;
  final bool isCollectionGroup;

  bool _inScope(String documentPath) {
    final parent = _parentPath(documentPath);
    if (!isCollectionGroup) return parent == collectionPath;
    return parent.split('/').last == collectionPath;
  }

  FakeQueryPlatform _copyWith(Map<String, dynamic> changes) {
    return FakeQueryPlatform(
      _store,
      collectionPath,
      Map<String, dynamic>.of(parameters)..addAll(changes),
      isCollectionGroup: isCollectionGroup,
    );
  }

  @override
  bool get isCollectionGroupQuery => isCollectionGroup;

  @override
  QueryPlatform where(List<List<dynamic>> conditions) =>
      _copyWith(<String, dynamic>{'where': conditions});

  @override
  QueryPlatform orderBy(Iterable<List<dynamic>> orders) =>
      _copyWith(<String, dynamic>{'orderBy': orders.toList()});

  @override
  QueryPlatform limit(int limit) =>
      _copyWith(<String, dynamic>{'limit': limit});

  static String _fieldName(Object? field) {
    if (field is FieldPath) return field.components.join('.');
    return field.toString();
  }

  bool _matches(Map<String, dynamic> data) {
    final conditions = (parameters['where'] as List?) ?? const <dynamic>[];
    for (final raw in conditions) {
      final condition = raw as List<dynamic>;
      final field = _fieldName(condition[0]);
      final operator = condition[1];
      final expected = condition[2];
      final actual = data[field];

      if (operator == '==' && actual != expected) return false;
      if (operator == '!=' && actual == expected) return false;
      if (operator != '==' && operator != '!=') {
        throw UnsupportedError(
          'FakeQueryPlatform does not support operator "$operator".',
        );
      }
    }
    return true;
  }

  @override
  Future<QuerySnapshotPlatform> get([
    GetOptions options = const GetOptions(),
  ]) async {
    final docs = <DocumentSnapshotPlatform>[];

    _store.documents.forEach((path, data) {
      if (_inScope(path) && _matches(data)) {
        docs.add(
          DocumentSnapshotPlatform(
            _store,
            path,
            Map<String?, Object?>.of(data),
            _metadata(),
          ),
        );
      }
    });

    final limit = parameters['limit'];
    final limited = limit is int && docs.length > limit
        ? docs.sublist(0, limit)
        : docs;

    return QuerySnapshotPlatform(
      limited,
      <DocumentChangePlatform>[],
      SnapshotMetadataPlatform(false, false),
    );
  }

  @override
  Stream<QuerySnapshotPlatform> snapshots({
    bool includeMetadataChanges = false,
    required ListenSource listenSource,
  }) =>
      Stream<QuerySnapshotPlatform>.fromFuture(get());
}

class FakeCollectionReferencePlatform extends CollectionReferencePlatform {
  FakeCollectionReferencePlatform(this._store, String path)
      : super(_store, path);

  final FakeFirebaseFirestorePlatform _store;

  FakeQueryPlatform get _query => FakeQueryPlatform(
        _store,
        path,
        Map<String, dynamic>.of(_defaultQueryParameters),
      );

  // CollectionReferencePlatform passes an empty parameter map to its parent;
  // the real cloud_firestore Query API expects the standard keys.
  @override
  Map<String, dynamic> get parameters => _defaultQueryParameters;

  @override
  bool get isCollectionGroupQuery => false;

  @override
  DocumentReferencePlatform doc([String? path]) =>
      FakeDocumentReferencePlatform(
        _store,
        '${this.path}/${path ?? _store.nextAutoId()}',
      );

  @override
  QueryPlatform where(List<List<dynamic>> conditions) =>
      _query.where(conditions);

  @override
  QueryPlatform orderBy(Iterable<List<dynamic>> orders) =>
      _query.orderBy(orders);

  @override
  QueryPlatform limit(int limit) => _query.limit(limit);

  @override
  Future<QuerySnapshotPlatform> get([
    GetOptions options = const GetOptions(),
  ]) =>
      _query.get(options);

  @override
  Stream<QuerySnapshotPlatform> snapshots({
    bool includeMetadataChanges = false,
    required ListenSource listenSource,
  }) =>
      _query.snapshots(listenSource: listenSource);
}
