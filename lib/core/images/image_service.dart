import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:image_picker/image_picker.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'image_models.dart';

part 'image_service.g.dart';

/// Picks an image and compresses it for upload.
///
/// An interface so the widgets can be driven by a fake: a real picker needs a
/// platform channel, which no widget test has.
abstract interface class ImageService {
  Future<PickedImage?> pick(ImageSourceKind source);
}

class PlatformImageService implements ImageService {
  PlatformImageService({ImagePicker? picker})
    : _picker = picker ?? ImagePicker();

  final ImagePicker _picker;

  /// Spec §3: at most 1600px on the long edge, JPEG quality 80.
  static const int maxLongEdge = 1600;
  static const int jpegQuality = 80;

  @override
  Future<PickedImage?> pick(ImageSourceKind source) async {
    // In a browser the picker resizes on a canvas itself; the native
    // compressor would need an extra JavaScript library there (D-71).
    final file = await _picker.pickImage(
      source: switch (source) {
        ImageSourceKind.camera => ImageSource.camera,
        ImageSourceKind.gallery => ImageSource.gallery,
      },
      maxWidth: kIsWeb ? maxLongEdge.toDouble() : null,
      maxHeight: kIsWeb ? maxLongEdge.toDouble() : null,
      imageQuality: kIsWeb ? jpegQuality : null,
    );
    if (file == null) return null;

    final original = await file.readAsBytes();
    if (kIsWeb) {
      final type = file.mimeType ?? 'image/jpeg';
      return PickedImage(
        bytes: original,
        contentType: type,
        extension: switch (type) {
          'image/png' => 'png',
          'image/webp' => 'webp',
          _ => 'jpg',
        },
      );
    }
    return compress(original);
  }

  /// Scales the long edge down to [maxLongEdge] and re-encodes as JPEG.
  ///
  /// The target dimensions are computed here rather than left to the
  /// compressor's own min-size rule: passing exact values makes the result the
  /// same whatever that rule happens to be, which matters because "long edge"
  /// is what the spec asks for and the compressor thinks in width and height.
  static Future<PickedImage> compress(Uint8List original) async {
    final (width, height) = await _dimensions(original);
    final longEdge = math.max(width, height);

    var targetWidth = width;
    var targetHeight = height;
    if (longEdge > maxLongEdge && longEdge > 0) {
      final scale = maxLongEdge / longEdge;
      targetWidth = math.max(1, (width * scale).round());
      targetHeight = math.max(1, (height * scale).round());
    }

    try {
      final compressed = await FlutterImageCompress.compressWithList(
        original,
        minWidth: targetWidth,
        minHeight: targetHeight,
        quality: jpegQuality,
        format: CompressFormat.jpeg,
      );
      return PickedImage(bytes: Uint8List.fromList(compressed));
    } on Exception catch (error) {
      // A format the compressor cannot read is better uploaded as-is than
      // dropped on the floor — the bucket caps the size anyway.
      debugPrint('Image compression failed, uploading original: $error');
      return PickedImage(bytes: original);
    }
  }

  static Future<(int, int)> _dimensions(Uint8List bytes) async {
    final codec = await ui.instantiateImageCodec(bytes);
    try {
      final frame = await codec.getNextFrame();
      try {
        return (frame.image.width, frame.image.height);
      } finally {
        frame.image.dispose();
      }
    } finally {
      codec.dispose();
    }
  }
}

@Riverpod(keepAlive: true)
ImageService imageService(Ref ref) => PlatformImageService();
