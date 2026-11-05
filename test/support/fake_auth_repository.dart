import 'dart:async';

import 'package:hati/features/auth/data/auth_repository.dart';
import 'package:hati/features/auth/domain/auth_failure.dart';
import 'package:hati/features/auth/domain/auth_snapshot.dart';

/// An in-memory [AuthRepository] for tests.
///
/// Records what it was asked to do and can be told to fail, so the screens and
/// the router can be driven without a live Supabase project.
class FakeAuthRepository implements AuthRepository {
  FakeAuthRepository({AuthSnapshot? initial})
    : _snapshot = initial ?? const AuthSnapshot.signedOut();

  final _controller = StreamController<AuthSnapshot>.broadcast();
  AuthSnapshot _snapshot;

  /// When set, the next call throws this instead of succeeding.
  AuthFailure? failWith;

  final List<String> calls = <String>[];
  String? lastEmail;
  String? lastPassword;
  String? lastDisplayName;

  @override
  AuthSnapshot get snapshot => _snapshot;

  @override
  Stream<AuthSnapshot> get changes => _controller.stream;

  /// Simulates the session changing, the way Supabase would push it.
  void emit(AuthSnapshot next) {
    _snapshot = next;
    _controller.add(next);
  }

  void signInAs(String userId) =>
      emit(AuthSnapshot(userId: userId, emailConfirmed: true));

  Future<void> dispose() => _controller.close();

  @override
  Future<void> signUp({
    required String email,
    required String password,
    required String displayName,
  }) async {
    calls.add('signUp');
    lastEmail = email;
    lastPassword = password;
    lastDisplayName = displayName;
    _maybeFail();
  }

  @override
  Future<void> signIn({required String email, required String password}) async {
    calls.add('signIn');
    lastEmail = email;
    lastPassword = password;
    _maybeFail();
  }

  @override
  Future<void> signInWithGoogle() async {
    calls.add('signInWithGoogle');
    _maybeFail();
  }

  @override
  Future<void> updatePassword(String password) async {
    calls.add('updatePassword');
    lastPassword = password;
    _maybeFail();
    final current = _snapshot;
    emit(
      AuthSnapshot(
        userId: current.userId,
        emailConfirmed: current.emailConfirmed,
      ),
    );
  }

  @override
  Future<void> sendPasswordReset(String email) async {
    calls.add('sendPasswordReset');
    lastEmail = email;
    _maybeFail();
  }

  @override
  Future<void> resendConfirmation(String email) async {
    calls.add('resendConfirmation');
    lastEmail = email;
    _maybeFail();
  }

  @override
  Future<void> signOut() async {
    calls.add('signOut');
    _maybeFail();
    emit(const AuthSnapshot.signedOut());
  }

  void _maybeFail() {
    final failure = failWith;
    if (failure != null) {
      failWith = null;
      throw failure;
    }
  }
}
