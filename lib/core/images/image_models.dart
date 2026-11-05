import 'dart:typed_data';

/// Where an image came from.
///
/// Its own enum rather than image_picker's `ImageSource`, so the picker
/// package stops at the implementation and never reaches the widgets or their
/// tests.
enum ImageSourceKind { camera, gallery }

/// An image that has been picked and compressed, ready to upload.
class PickedImage {
  const PickedImage({
    required this.bytes,
    this.contentType = 'image/jpeg',
    this.extension = 'jpg',
  });

  final Uint8List bytes;
  final String contentType;
  final String extension;

  int get sizeInBytes => bytes.length;
}

/// The private buckets from spec §5.2.
enum StorageBucket {
  avatars('avatars'),
  groupPhotos('group-photos'),
  paymentQr('payment-qr'),
  billReceipts('bill-receipts'),
  paymentProofs('payment-proofs');

  const StorageBucket(this.id);

  final String id;
}

/// Object paths.
///
/// Every path starts with the id that scopes it, because the storage policies
/// authorise by parsing the first segment (spec §5.2). Getting a path wrong
/// does not leak anything — the policy simply refuses — but it does mean the
/// upload fails, so the shapes live here rather than at each call site.
abstract final class StoragePaths {
  static String avatar(String userId, String filename) => '$userId/$filename';

  static String paymentQr(String userId, String filename) =>
      '$userId/$filename';

  static String groupPhoto(String groupId, String filename) =>
      '$groupId/$filename';

  static String billReceipt({
    required String groupId,
    required String billId,
    required String filename,
  }) => '$groupId/$billId/$filename';

  static String paymentProof({
    required String groupId,
    required String filename,
  }) => '$groupId/$filename';
}
