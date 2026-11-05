import 'dart:convert';
import 'dart:typed_data';

import 'package:hati/core/images/attachment_storage.dart';
import 'package:hati/core/images/image_gallery.dart';
import 'package:hati/core/images/image_models.dart';
import 'package:hati/core/images/image_service.dart';

/// An [ImageService] that returns a fixed image without touching a platform
/// channel — no widget test has a camera.
class FakeImageService implements ImageService {
  FakeImageService({PickedImage? result})
    : result = result ?? PickedImage(bytes: _onePixelJpeg);

  /// The user opened the picker and backed out.
  ///
  /// A named constructor rather than `result: null`, which the `??` default
  /// above would silently turn back into an image.
  FakeImageService.cancelling() : result = null;

  PickedImage? result;

  final List<ImageSourceKind> requested = <ImageSourceKind>[];

  @override
  Future<PickedImage?> pick(ImageSourceKind source) async {
    requested.add(source);
    return result;
  }
}

/// A real 1x1 transparent PNG.
///
/// It has to decode: anything that renders a picked image calls
/// `Image.memory`, and invented bytes fail with "Invalid image data".
final Uint8List _onePixelJpeg = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhf'
  'DwAChwGA60e6kgAAAABJRU5ErkJggg==',
);

/// Records uploads instead of performing them.
class FakeAttachmentStorage implements AttachmentStorage {
  AttachmentFailure? failWith;

  final List<({StorageBucket bucket, String path})> uploads = [];
  final List<({StorageBucket bucket, String path})> removals = [];
  int _counter = 0;

  final List<({StorageBucket bucket, String path})> downloads = [];

  @override
  Future<Uint8List> download({
    required StorageBucket bucket,
    required String path,
  }) async {
    final failure = failWith;
    if (failure != null) {
      failWith = null;
      throw failure;
    }
    downloads.add((bucket: bucket, path: path));
    return _onePixelJpeg;
  }

  @override
  String newFilename({String extension = 'jpg'}) =>
      'file-${++_counter}.$extension';

  @override
  Future<void> upload({
    required StorageBucket bucket,
    required String path,
    required PickedImage image,
  }) async {
    final failure = failWith;
    if (failure != null) {
      failWith = null;
      throw failure;
    }
    uploads.add((bucket: bucket, path: path));
  }

  @override
  Future<String> signedUrl({
    required StorageBucket bucket,
    required String path,
    Duration expiresIn = const Duration(hours: 1),
  }) async => 'https://signed.test/${bucket.id}/$path';

  @override
  Future<void> remove({
    required StorageBucket bucket,
    required String path,
  }) async {
    removals.add((bucket: bucket, path: path));
  }
}

/// Records what would have gone to the photo gallery.
class FakeImageGallery implements ImageGallery {
  final List<String> saved = <String>[];
  GalleryFailure? failWith;

  @override
  Future<void> save(Uint8List bytes, {required String name}) async {
    final failure = failWith;
    if (failure != null) {
      failWith = null;
      throw failure;
    }
    saved.add(name);
  }
}
