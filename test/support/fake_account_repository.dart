import 'package:hati/features/auth/domain/auth_snapshot.dart';
import 'package:hati/features/profile/data/account_repository.dart';

import 'fake_auth_repository.dart';

/// An in-memory [AccountRepository] for tests.
class FakeAccountRepository implements AccountRepository {
  FakeAccountRepository({List<DeletionBlocker>? blockers})
    : blockers = blockers ?? <DeletionBlocker>[];

  final List<DeletionBlocker> blockers;
  final List<String> calls = <String>[];
  AccountDeletionFailure? failWith;

  /// Set by the harness so a successful deletion ends the session, as the
  /// real one does.
  FakeAuthRepository? auth;

  @override
  Future<List<DeletionBlocker>> deletionBlockers() async {
    calls.add('deletionBlockers');
    return blockers;
  }

  @override
  Future<void> deleteAccount() async {
    calls.add('deleteAccount');
    final failure = failWith;
    if (failure != null) {
      failWith = null;
      throw failure;
    }
    auth?.emit(const AuthSnapshot.signedOut());
  }
}
