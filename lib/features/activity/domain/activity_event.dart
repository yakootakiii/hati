import 'package:freezed_annotation/freezed_annotation.dart';

import '../../../core/money/money.dart';

part 'activity_event.freezed.dart';
part 'activity_event.g.dart';

/// The event types from spec §5.3.
enum ActivityType {
  groupCreated('group_created'),
  memberJoined('member_joined'),
  memberLeft('member_left'),
  memberRemoved('member_removed'),
  billCreated('bill_created'),
  billEdited('bill_edited'),
  billVoided('bill_voided'),
  paymentMarked('payment_marked'),
  paymentConfirmed('payment_confirmed'),
  paymentRejected('payment_rejected'),
  billSettled('bill_settled'),
  commentAdded('comment_added'),
  recurringCreated('recurring_created'),
  recurringGenerated('recurring_generated'),
  unknown('unknown');

  const ActivityType(this.wire);

  final String wire;

  static ActivityType fromWire(String value) => ActivityType.values.firstWhere(
        (t) => t.wire == value,
        orElse: () => ActivityType.unknown,
      );
}

/// One entry in a feed.
@freezed
abstract class ActivityEvent with _$ActivityEvent {
  const factory ActivityEvent({
    required String id,
    required String groupId,
    required String groupName,
    required String type,
    required DateTime createdAt,
    String? actorId,
    String? actorName,
    String? billId,
    String? paymentId,
    String? commentId,
    @Default(<String, dynamic>{}) Map<String, dynamic> payload,
  }) = _ActivityEvent;

  const ActivityEvent._();

  factory ActivityEvent.fromJson(Map<String, dynamic> json) =>
      _$ActivityEventFromJson(json);

  ActivityType get kind => ActivityType.fromWire(type);

  String get actor => actorName ?? 'Someone';

  String? get billTitle => payload['bill_title'] as String?;

  /// Whoever the event is about, when that differs from the actor — the person
  /// who joined, left, or was removed.
  String? get subject => payload['display_name'] as String?;

  Money? get amount {
    // Payload amounts are written from a bigint column, so they arrive as
    // integer centavos. Anything else is ignored rather than truncated — a
    // rounded amount in a feed entry would be worse than no amount at all.
    final raw = payload['amount'];
    return raw is int ? Money(raw) : null;
  }

  String? get reason {
    final raw = payload['reason'] as String?;
    return (raw == null || raw.isEmpty) ? null : raw;
  }

  String? get excerpt => payload['excerpt'] as String?;

  /// Tapping the entry goes here, or nowhere when the event has no bill.
  String? get route => billId == null ? null : '/bills/$billId';

  /// One line of plain copy (spec §11: friendly, plain, lightly casual).
  ///
  /// Everything comes from the denormalised payload, so an entry still reads
  /// correctly after the bill is voided or the comment deleted.
  String describe({required bool actorIsMe}) {
    final who = actorIsMe ? 'You' : actor;
    final title = billTitle ?? 'a bill';
    final money = amount?.format();

    return switch (kind) {
      ActivityType.groupCreated =>
        '$who created ${payload['group_name'] ?? 'the group'}',
      ActivityType.memberJoined =>
        actorIsMe ? 'You joined' : '${subject ?? actor} joined',
      ActivityType.memberLeft =>
        actorIsMe ? 'You left' : '${subject ?? actor} left',
      ActivityType.memberRemoved =>
        '${subject ?? 'Someone'} was removed by $who',
      ActivityType.billCreated => money == null
          ? '$who added $title'
          : '$who added $title · $money',
      ActivityType.billEdited => '$who updated $title',
      ActivityType.billVoided => reason == null
          ? '$who voided $title'
          : '$who voided $title — $reason',
      ActivityType.paymentMarked => money == null
          ? '$who marked their share of $title as paid'
          : '$who marked $money as paid for $title',
      ActivityType.paymentConfirmed => money == null
          ? '$who confirmed a payment for $title'
          : '$who confirmed $money for $title',
      ActivityType.paymentRejected => reason == null
          ? "$who couldn't find a payment for $title"
          : "$who couldn't find a payment for $title — $reason",
      ActivityType.billSettled => '$title is fully settled',
      ActivityType.commentAdded => excerpt == null
          ? '$who commented on $title'
          : '$who commented on $title: $excerpt',
      ActivityType.recurringCreated => '$who set up $title to repeat',
      ActivityType.recurringGenerated => '$title was added automatically',
      ActivityType.unknown => 'Something happened',
    };
  }
}
