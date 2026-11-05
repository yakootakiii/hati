import 'dart:io' show SocketException;

import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/supabase/supabase_providers.dart';
import '../domain/profile.dart';

part 'profile_repository.g.dart';

class ProfileFailure implements Exception {
  const ProfileFailure(this.message);

  final String message;

  @override
  String toString() => 'ProfileFailure: $message';
}

abstract interface class ProfileRepository {
  Future<Profile?> mine();

  /// Only the fields passed are changed.
  Future<void> update({String? displayName, String? avatarPath});
}

class SupabaseProfileRepository implements ProfileRepository {
  SupabaseProfileRepository(this._client);

  final SupabaseClient _client;

  String? get _userId => _client.auth.currentUser?.id;

  @override
  Future<Profile?> mine() {
    return _guard(() async {
      final id = _userId;
      if (id == null) return null;
      final row =
          await _client.from('profiles').select().eq('id', id).maybeSingle();
      return row == null ? null : Profile.fromJson(row);
    });
  }

  @override
  Future<void> update({String? displayName, String? avatarPath}) {
    return _guard(() async {
      final patch = <String, dynamic>{
        if (displayName != null) 'display_name': displayName,
        // An explicit empty string clears the avatar; null means leave it.
        if (avatarPath != null)
          'avatar_path': avatarPath.isEmpty ? null : avatarPath,
      };
      if (patch.isEmpty) return;
      await _client.from('profiles').update(patch).eq('id', _userId!);
    });
  }

  static Future<T> _guard<T>(Future<T> Function() action) async {
    try {
      return await action();
    } on PostgrestException catch (error) {
      throw ProfileFailure(error.message);
    } on SocketException catch (_) {
      throw const ProfileFailure("Can't reach Hati right now.");
    }
  }
}

@Riverpod(keepAlive: true)
ProfileRepository profileRepository(Ref ref) {
  if (!ref.watch(isBackendConfiguredProvider)) {
    throw StateError('Profiles need a Supabase project.');
  }
  return SupabaseProfileRepository(Supabase.instance.client);
}

@riverpod
Future<Profile?> myProfile(Ref ref) =>
    ref.watch(profileRepositoryProvider).mine();

@Riverpod(keepAlive: true)
class ProfileActions extends _$ProfileActions {
  @override
  FutureOr<void> build() {}

  String? lastError;

  Future<bool> save({String? displayName, String? avatarPath}) async {
    state = const AsyncValue<void>.loading();
    try {
      await ref.read(profileRepositoryProvider).update(
            displayName: displayName,
            avatarPath: avatarPath,
          );
      ref.invalidate(myProfileProvider);
      lastError = null;
      state = const AsyncValue<void>.data(null);
      return true;
    } on ProfileFailure catch (failure, stackTrace) {
      lastError = failure.message;
      state = AsyncValue<void>.error(failure, stackTrace);
      return false;
    }
  }
}
