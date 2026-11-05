import 'dart:typed_data';
import 'dart:io' show SocketException;

import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../supabase/supabase_providers.dart';
import 'image_models.dart';

part 'attachment_storage.g.dart';

class AttachmentFailure implements Exception {
  const AttachmentFailure(this.message);

  final String message;

  @override
  String toString() => 'AttachmentFailure: $message';
}

/// Uploads to and reads from the private buckets.
///
/// Every bucket is private, so reads go through short-lived signed URLs
/// (spec §5.2). Storage RLS decides whether a URL can be signed at all.
abstract interface class AttachmentStorage {
  Future<void> upload({
    required StorageBucket bucket,
    required String path,
    required PickedImage image,
  });

  Future<String> signedUrl({
    required StorageBucket bucket,
    required String path,
    Duration expiresIn,
  });

  Future<void> remove({required StorageBucket bucket, required String path});

  /// The stored bytes — for saving a payer's QR to the gallery (D-68).
  Future<Uint8List> download({
    required StorageBucket bucket,
    required String path,
  });

  /// A collision-proof name for a new object.
  String newFilename({String extension = 'jpg'});
}

class SupabaseAttachmentStorage implements AttachmentStorage {
  SupabaseAttachmentStorage(this._client);

  final SupabaseClient _client;
  static const _uuid = Uuid();

  @override
  String newFilename({String extension = 'jpg'}) => '${_uuid.v4()}.$extension';

  @override
  Future<void> upload({
    required StorageBucket bucket,
    required String path,
    required PickedImage image,
  }) {
    return _guard(() async {
      await _client.storage
          .from(bucket.id)
          .uploadBinary(
            path,
            image.bytes,
            fileOptions: FileOptions(
              contentType: image.contentType,
              upsert: false,
            ),
          );
    });
  }

  @override
  Future<String> signedUrl({
    required StorageBucket bucket,
    required String path,
    Duration expiresIn = const Duration(hours: 1),
  }) {
    return _guard(
      () => _client.storage
          .from(bucket.id)
          .createSignedUrl(path, expiresIn.inSeconds),
    );
  }

  @override
  Future<void> remove({required StorageBucket bucket, required String path}) {
    return _guard(() async {
      await _client.storage.from(bucket.id).remove([path]);
    });
  }

  @override
  Future<Uint8List> download({
    required StorageBucket bucket,
    required String path,
  }) => _guard(() => _client.storage.from(bucket.id).download(path));

  static Future<T> _guard<T>(Future<T> Function() action) async {
    try {
      return await action();
    } on StorageException catch (error) {
      throw AttachmentFailure(error.message);
    } on SocketException catch (_) {
      throw const AttachmentFailure("Can't reach Hati right now.");
    }
  }
}

@Riverpod(keepAlive: true)
AttachmentStorage attachmentStorage(Ref ref) {
  if (!ref.watch(isBackendConfiguredProvider)) {
    throw StateError('Attachments need a Supabase project.');
  }
  return SupabaseAttachmentStorage(Supabase.instance.client);
}

/// A signed URL for one object, cached for as long as the screen is open.
@riverpod
Future<String> signedAttachmentUrl(
  Ref ref,
  StorageBucket bucket,
  String path,
) => ref.watch(attachmentStorageProvider).signedUrl(bucket: bucket, path: path);
