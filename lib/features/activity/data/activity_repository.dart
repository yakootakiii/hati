import 'dart:io' show SocketException;

import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/supabase/supabase_providers.dart';
import '../domain/activity_event.dart';
import '../domain/comment.dart';

part 'activity_repository.g.dart';

class ActivityFailure implements Exception {
  const ActivityFailure(this.message);

  final String message;

  @override
  String toString() => 'ActivityFailure: $message';
}

/// The feed and the comment thread (spec §10).
abstract interface class ActivityRepository {
  /// [groupId] null gives the merged feed across every group the caller is in.
  ///
  /// [before] pages backwards through time, which stays correct while new
  /// events keep arriving — an offset would not.
  Future<List<ActivityEvent>> feed({
    String? groupId,
    int limit = 30,
    DateTime? before,
  });

  Future<List<Comment>> comments(String billId);

  Future<void> addComment({required String billId, required String body});

  Future<void> editComment({required String commentId, required String body});

  /// Soft delete: the row stays so the thread keeps its shape.
  Future<void> deleteComment(String commentId);
}

class SupabaseActivityRepository implements ActivityRepository {
  SupabaseActivityRepository(this._client);

  final SupabaseClient _client;

  @override
  Future<List<ActivityEvent>> feed({
    String? groupId,
    int limit = 30,
    DateTime? before,
  }) {
    return _guard(() async {
      final rows = await _client.rpc<List<dynamic>>(
        'get_activity_feed',
        params: {
          'p_group_id': groupId,
          'p_limit': limit,
          'p_before': before?.toUtc().toIso8601String(),
        },
      );
      return rows
          .cast<Map<String, dynamic>>()
          .map(ActivityEvent.fromJson)
          .toList(growable: false);
    });
  }

  @override
  Future<List<Comment>> comments(String billId) {
    return _guard(() async {
      final rows = await _client
          .from('comments')
          .select(
            'id, bill_id, author_id, body, edited_at, deleted_at, created_at, '
            'profiles(display_name, avatar_path)',
          )
          .eq('bill_id', billId)
          .order('created_at');

      return rows.map((row) {
        final profile = row['profiles'] as Map<String, dynamic>?;
        return Comment(
          id: row['id'] as String,
          billId: row['bill_id'] as String,
          authorId: row['author_id'] as String,
          body: row['body'] as String,
          authorName: profile?['display_name'] as String?,
          authorAvatarPath: profile?['avatar_path'] as String?,
          editedAt: DateTime.tryParse(row['edited_at'] as String? ?? ''),
          deletedAt: DateTime.tryParse(row['deleted_at'] as String? ?? ''),
          createdAt: DateTime.parse(row['created_at'] as String),
        );
      }).toList(growable: false);
    });
  }

  @override
  Future<void> addComment({required String billId, required String body}) {
    return _guard(() async {
      // The insert policy requires author_id = auth.uid(), so a forged author
      // is refused rather than quietly accepted.
      await _client.from('comments').insert({
        'bill_id': billId,
        'author_id': _client.auth.currentUser?.id,
        'body': body,
      });
    });
  }

  @override
  Future<void> editComment({
    required String commentId,
    required String body,
  }) {
    // edited_at is set by a trigger, not here — the client does not get to
    // decide whether an edit happened.
    return _guard(
      () => _client.from('comments').update({'body': body}).eq('id', commentId),
    );
  }

  @override
  Future<void> deleteComment(String commentId) => _guard(
        () => _client
            .from('comments')
            .update({'deleted_at': DateTime.now().toUtc().toIso8601String()})
            .eq('id', commentId),
      );

  static Future<T> _guard<T>(Future<T> Function() action) async {
    try {
      return await action();
    } on PostgrestException catch (error) {
      throw ActivityFailure(error.message);
    } on SocketException catch (_) {
      throw const ActivityFailure("Can't reach Hati right now.");
    }
  }
}

@Riverpod(keepAlive: true)
ActivityRepository activityRepository(Ref ref) {
  if (!ref.watch(isBackendConfiguredProvider)) {
    throw StateError('Activity needs a Supabase project.');
  }
  return SupabaseActivityRepository(Supabase.instance.client);
}
