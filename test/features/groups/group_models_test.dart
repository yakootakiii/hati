import 'package:flutter_test/flutter_test.dart';
import 'package:hati/features/groups/domain/group_failure.dart';
import 'package:hati/features/groups/domain/group_models.dart';

void main() {
  group('InviteLink', () {
    test('builds the shareable URL from the token (spec §8)', () {
      const link = InviteLink(id: 'i1', token: 'abc123');
      expect(link.url, 'https://hati-a1a23.web.app/join/abc123');
    });

    test('knows when it is spent', () {
      const unlimited = InviteLink(id: 'i', token: 't', useCount: 99);
      expect(unlimited.isExhausted, isFalse, reason: 'null maxUses is no limit');

      const spent = InviteLink(id: 'i', token: 't', maxUses: 2, useCount: 2);
      expect(spent.isExhausted, isTrue);

      final expired = InviteLink(
        id: 'i',
        token: 't',
        expiresAt: DateTime.now().toUtc().subtract(const Duration(hours: 1)),
      );
      expect(expired.isExpired, isTrue);
    });
  });

  group('InvitePreview.fromJson', () {
    test('reads a usable invite', () {
      final preview = InvitePreview.fromJson({
        'valid': true,
        'group_id': 'g1',
        'group_name': 'Tagaytay Staycation',
        'member_count': 4,
        'already_member': false,
        'inviter_name': 'Bea',
      });

      expect(preview, isA<ValidInvitePreview>());
      final valid = preview as ValidInvitePreview;
      expect(valid.groupName, 'Tagaytay Staycation');
      expect(valid.memberCount, 4);
      expect(valid.inviterName, 'Bea');
    });

    test('maps each refusal reason, carrying no group details', () {
      for (final (reason, expected) in [
        ('revoked', InviteInvalidReason.revoked),
        ('expired', InviteInvalidReason.expired),
        ('exhausted', InviteInvalidReason.exhausted),
        ('not_found', InviteInvalidReason.notFound),
        (null, InviteInvalidReason.notFound),
      ]) {
        final preview = InvitePreview.fromJson({
          'valid': false,
          if (reason != null) 'reason': reason,
        });
        expect(preview, isA<InvalidInvitePreview>());
        expect((preview as InvalidInvitePreview).reason, expected);
      }
    });
  });

  group('GroupFailure', () {
    test('maps every HT code the RPCs raise', () {
      const expected = {
        'HT001': GroupFailureKind.notAMember,
        'HT002': GroupFailureKind.notAuthorized,
        'HT003': GroupFailureKind.inviteNotFound,
        'HT004': GroupFailureKind.inviteExpired,
        'HT005': GroupFailureKind.inviteRevoked,
        'HT006': GroupFailureKind.inviteExhausted,
        'HT007': GroupFailureKind.outstandingBalance,
        'HT008': GroupFailureKind.ownerMustTransfer,
        'HT009': GroupFailureKind.cannotRemoveOwner,
        'HT010': GroupFailureKind.invalidInput,
      };

      expected.forEach((code, kind) {
        expect(GroupFailure.fromCode(code, 'x').kind, kind, reason: code);
      });
      expect(
        GroupFailure.fromCode('42501', 'x').kind,
        GroupFailureKind.unknown,
      );
      expect(GroupFailure.fromCode(null, 'x').kind, GroupFailureKind.unknown);
    });

    test('each invite refusal tells the user to ask for a new link', () {
      for (final code in ['HT003', 'HT004', 'HT005', 'HT006']) {
        expect(
          GroupFailure.fromCode(code, 'raw').displayMessage,
          contains('Ask for a new one'),
          reason: code,
        );
      }
    });

    test('an outstanding balance keeps the server message, which names the bills',
        () {
      final failure =
          GroupFailure.fromCode('HT007', 'Settle up first: Airbnb – 2 nights');
      expect(failure.displayMessage, contains('Airbnb'));
    });
  });

  group('GroupSummary', () {
    test('derives permissions from the role', () {
      const owner = GroupSummary(id: 'g', name: 'G', role: 'owner', memberCount: 1);
      const admin = GroupSummary(id: 'g', name: 'G', role: 'admin', memberCount: 1);
      const member = GroupSummary(id: 'g', name: 'G', role: 'member', memberCount: 1);

      expect(owner.isOwner, isTrue);
      expect(owner.canInvite, isTrue);
      expect(admin.canInvite, isTrue);
      expect(admin.isOwner, isFalse);
      expect(member.canInvite, isFalse);
    });

    test('parses the shape get_my_groups returns', () {
      final summary = GroupSummary.fromJson({
        'id': 'g1',
        'name': 'Tagaytay Staycation',
        'role': 'owner',
        'member_count': 4,
        'photo_path': null,
        'archived_at': '2026-01-02T03:04:05Z',
        'members': [
          {'id': 'u1', 'display_name': 'Bea', 'avatar_path': null},
        ],
      });

      expect(summary.name, 'Tagaytay Staycation');
      expect(summary.memberCount, 4);
      expect(summary.isArchived, isTrue);
      expect(summary.members.single.displayName, 'Bea');
    });
  });
}
