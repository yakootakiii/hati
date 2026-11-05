import 'package:flutter/foundation.dart';
import 'package:gal/gal.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'browser_download_stub.dart'
    if (dart.library.js_interop) 'browser_download_web.dart';

part 'image_gallery.g.dart';

class GalleryFailure implements Exception {
  const GalleryFailure(this.message);
  final String message;

  @override
  String toString() => 'GalleryFailure: $message';
}

/// Saving images to the phone's photo gallery (DECISIONS D-68): most people
/// pay a QR by opening it from the gallery inside GCash or Maya.
abstract interface class ImageGallery {
  Future<void> save(Uint8List bytes, {required String name});
}

class GalImageGallery implements ImageGallery {
  const GalImageGallery();

  @override
  Future<void> save(Uint8List bytes, {required String name}) async {
    try {
      if (!await Gal.hasAccess() && !await Gal.requestAccess()) {
        throw const GalleryFailure(
          'Hati needs permission to save photos. Allow it in Settings.',
        );
      }
      await Gal.putImageBytes(bytes, name: name);
    } on GalException catch (error) {
      throw GalleryFailure(error.type.message);
    }
  }
}

/// The web version (D-71): browsers have no photo gallery to write to, so
/// the QR is downloaded instead.
class BrowserDownloadGallery implements ImageGallery {
  const BrowserDownloadGallery();

  @override
  Future<void> save(Uint8List bytes, {required String name}) async {
    final safe = name.replaceAll(RegExp(r'[^A-Za-z0-9 ._-]'), '').trim();
    downloadInBrowser(
      bytes,
      '${safe.isEmpty ? 'Hati QR' : safe}.png',
      'image/png',
    );
  }
}

@Riverpod(keepAlive: true)
ImageGallery imageGallery(Ref ref) =>
    kIsWeb ? const BrowserDownloadGallery() : const GalImageGallery();
