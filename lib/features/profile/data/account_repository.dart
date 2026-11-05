import 'dart:io' show SocketException;

import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/money/money.dart';
import '../../../core/supabase/supabase_providers.dart';

part 'account_repository.g.dart';

/// A bill that has to be settled before the account can go (HT057).
class DeletionBlocker {
  const DeletionBlocker({
    required this.groupName,
    required this.title,
    required this.youOwe,
    required this.amount,
  });

  final String groupName;
  final String title;

  /// True when the user owes it; false when they are owed it.
  final bool youOwe;
  final Money amount;
}

class AccountDeletionFailure implements Exception {
  const AccountDeletionFailure(this.message);

  final String message;

  @override
  String toString() => 'AccountDeletionFailure: $message';
}

/// Deleting your own account (DECISIONS D-64).
abstract interface class AccountRepository {
  /// Open bills that stop the account being deleted. Empty means go ahead.
  Future<List<DeletionBlocker>> deletionBlockers();

  /// Erases the account through the delete-account edge function, then ends
  /// the session on this device.
  Future<void> deleteAccount();
}

class SupabaseAccountRepository implements AccountRepository {
  SupabaseAccountRepository(this._client);

  final SupabaseClient _client;

  @override
  Future<List<DeletionBlocker>> deletionBlockers() async {
    try {
      final rows =
          await _client.rpc<List<dynamic>>('account_deletion_blockers');
      return rows
          .cast<Map<String, dynamic>>()
          .map(
            (row) => DeletionBlocker(
              groupName: row['group_name'] as String,
              title: row['title'] as String,
              youOwe: row['reason'] == 'you_owe',
              amount: Money((row['amount'] as num).toInt()),
            ),
          )
          .toList(growable: false);
    } on PostgrestException catch (error) {
      throw AccountDeletionFailure(error.message);
    } on SocketException catch (_) {
      throw const AccountDeletionFailure("Can't reach Hati right now.");
    }
  }

  @override
  Future<void> deleteAccount() async {
    try {
      await _client.functions.invoke('delete-account');
    } on FunctionException catch (error) {
      throw AccountDeletionFailure(
        error.status == 409
            ? 'Settle your open bills first, then try again.'
            : 'Could not delete your account. Try again in a moment.',
      );
    } on SocketException catch (_) {
      throw const AccountDeletionFailure("Can't reach Hati right now.");
    }

    // The server has already ended the account; this only clears the
    // session stored on this phone.
    try {
      await _client.auth.signOut(scope: SignOutScope.local);
    } on AuthException catch (_) {
      // Nothing left to sign out of.
    }
  }
}

@Riverpod(keepAlive: true)
AccountRepository accountRepository(Ref ref) {
  if (!ref.watch(isBackendConfiguredProvider)) {
    throw StateError('Deleting an account needs a Supabase project.');
  }
  return SupabaseAccountRepository(Supabase.instance.client);
}

@riverpod
Future<List<DeletionBlocker>> deletionBlockers(Ref ref) =>
    ref.watch(accountRepositoryProvider).deletionBlockers();
