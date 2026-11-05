import 'package:flutter_test/flutter_test.dart';
import 'package:hati/core/images/image_models.dart';

/// The storage policies authorise by parsing the first path segment
/// (spec §5.2), so the shape of these paths is a security property, not a
/// formatting preference.
void main() {
  const user = '11111111-1111-1111-1111-111111111111';
  const group = '22222222-2222-2222-2222-222222222222';
  const bill = '33333333-3333-3333-3333-333333333333';

  String firstSegment(String path) => path.split('/').first;

  test('per-user objects are scoped by the owner id', () {
    expect(StoragePaths.avatar(user, 'me.jpg'), '$user/me.jpg');
    expect(StoragePaths.paymentQr(user, 'qr.jpg'), '$user/qr.jpg');

    expect(firstSegment(StoragePaths.avatar(user, 'me.jpg')), user);
    expect(firstSegment(StoragePaths.paymentQr(user, 'qr.jpg')), user);
  });

  test('group objects are scoped by the group id', () {
    expect(
      firstSegment(StoragePaths.groupPhoto(group, 'cover.jpg')),
      group,
    );
    expect(
      firstSegment(StoragePaths.paymentProof(groupId: group, filename: 'p.jpg')),
      group,
    );
    expect(
      firstSegment(
        StoragePaths.billReceipt(
          groupId: group,
          billId: bill,
          filename: 'r.jpg',
        ),
      ),
      group,
      reason: 'the policy reads segment 1, so the group must come first',
    );
  });

  test('a receipt keeps the bill id as its second segment', () {
    final path = StoragePaths.billReceipt(
      groupId: group,
      billId: bill,
      filename: 'r.jpg',
    );
    expect(path, '$group/$bill/r.jpg');
    expect(path.split('/')[1], bill);
  });

  test('bucket ids match the migration', () {
    expect(StorageBucket.avatars.id, 'avatars');
    expect(StorageBucket.groupPhotos.id, 'group-photos');
    expect(StorageBucket.paymentQr.id, 'payment-qr');
    expect(StorageBucket.billReceipts.id, 'bill-receipts');
    expect(StorageBucket.paymentProofs.id, 'payment-proofs');
  });
}
