import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hati/core/money/money.dart';
import 'package:hati/core/split/split.dart';
import 'package:hati/features/bills/presentation/bill_form_controller.dart';
import 'package:hati/features/bills/presentation/bills_controller.dart';
import 'package:hati/features/groups/domain/group_models.dart';

/// Bea joined first, then Carlo, then Dana — the order the split engine must
/// use (spec §6.1).
final members = [
  GroupMember(
    userId: 'bea',
    displayName: 'Bea',
    role: 'owner',
    joinedAt: DateTime.utc(2026, 1, 1),
  ),
  GroupMember(
    userId: 'carlo',
    displayName: 'Carlo',
    role: 'member',
    joinedAt: DateTime.utc(2026, 1, 2),
  ),
  GroupMember(
    userId: 'dana',
    displayName: 'Dana',
    role: 'member',
    joinedAt: DateTime.utc(2026, 1, 3),
  ),
];

void main() {
  late ProviderContainer container;

  setUp(() => container = ProviderContainer());
  tearDown(() => container.dispose());

  BillForm controller() => container.read(
        billFormProvider(groupId: 'g1', currentUserId: 'bea').notifier,
      );
  BillFormState state() => container.read(
        billFormProvider(groupId: 'g1', currentUserId: 'bea'),
      );

  group('canonical order (spec §6.1)', () {
    test('sorts by joined_at, then user id', () {
      final shuffled = [members[2], members[0], members[1]];
      expect(
        canonicalMemberOrder(shuffled).map((m) => m.userId),
        ['bea', 'carlo', 'dana'],
      );
    });

    test('falls back to user id when joined_at ties', () {
      final sameDay = [
        GroupMember(
          userId: 'zoe',
          displayName: 'Zoe',
          role: 'member',
          joinedAt: DateTime.utc(2026),
        ),
        GroupMember(
          userId: 'abe',
          displayName: 'Abe',
          role: 'member',
          joinedAt: DateTime.utc(2026),
        ),
      ];
      expect(
        canonicalMemberOrder(sameDay).map((m) => m.userId),
        ['abe', 'zoe'],
      );
    });

    test('the draft carries participants in that order, not selection order',
        () {
      controller()
        ..setTotal(const Money(10000))
        ..toggleParticipant('dana')
        ..toggleParticipant('bea')
        ..toggleParticipant('carlo');

      final draft = buildDraft(state(), members)!;
      expect(draft.participants.map((p) => p.userId), ['bea', 'carlo', 'dana']);
    });
  });

  group('live preview', () {
    test('matches what the engine will compute on the server', () {
      controller()
        ..setTotal(const Money(10000))
        ..selectAll(['bea', 'carlo', 'dana']);

      final preview = previewSplit(state(), members);
      expect(preview.failure, isNull);
      expect(preview.result!.toJson(), {
        'bea': 3334,
        'carlo': 3333,
        'dana': 3333,
      });
    });

    test('reports the reason while a split is still incomplete', () {
      controller()
        ..setTotal(const Money(100000))
        ..setMode(SplitMode.percent)
        ..selectAll(['bea', 'carlo'])
        ..setInput('bea', 5000);

      expect(
        previewSplit(state(), members).failure,
        SplitFailure.percentSumMismatch,
      );
    });

    test('has nothing to show before anyone is picked', () {
      controller().setTotal(const Money(10000));
      expect(
        previewSplit(state(), members).failure,
        SplitFailure.noParticipants,
      );
    });
  });

  group('switching mode', () {
    test('clears inputs, which mean different things per mode', () {
      controller()
        ..setTotal(const Money(100000))
        ..setMode(SplitMode.percent)
        ..selectAll(['bea', 'carlo'])
        ..setInput('bea', 5000)
        ..setInput('carlo', 5000);
      expect(state().inputs, isNotEmpty);

      controller().setMode(SplitMode.shares);
      expect(
        state().inputs,
        isEmpty,
        reason: '5000 hundredths-of-a-percent is not 5000 thousandths-of-a-share',
      );
    });
  });

  group('the remaining hint (spec §10)', () {
    test('counts down the pesos left to assign in exact mode', () {
      controller()
        ..setTotal(const Money(100000))
        ..setMode(SplitMode.exact)
        ..selectAll(['bea', 'carlo'])
        ..setInput('bea', 60000);

      final hint = assignmentRemainder(state())!;
      expect(hint.remaining, 40000);
      expect(hint.label, '₱400.00 left to assign');
    });

    test('says when exact amounts overshoot', () {
      controller()
        ..setTotal(const Money(100000))
        ..setMode(SplitMode.exact)
        ..selectAll(['bea'])
        ..setInput('bea', 150000);

      expect(assignmentRemainder(state())!.label, '₱500.00 over');
    });

    test('counts down percent to 100', () {
      controller()
        ..setTotal(const Money(100000))
        ..setMode(SplitMode.percent)
        ..selectAll(['bea', 'carlo'])
        ..setInput('bea', 3333);

      final hint = assignmentRemainder(state())!;
      expect(hint.remaining, 6667);
      expect(hint.label, '66.67% left');
    });

    test('is silent for modes with nothing to assign by hand', () {
      controller().setMode(SplitMode.equal);
      expect(assignmentRemainder(state()), isNull);

      controller().setMode(SplitMode.shares);
      expect(assignmentRemainder(state()), isNull);
    });
  });

  group('itemized totals (DECISIONS D-32)', () {
    test('the total is derived from the items and extras, never typed', () {
      controller()
        ..setMode(SplitMode.itemized)
        ..setTotal(const Money(999999))
        ..addItem();

      final key = state().items.single.key;
      controller()
        ..updateItem(key, (i) => i.copyWith(amount: const Money(30000)))
        ..setServiceCharge(const Money(3000))
        ..setDiscount(const Money(1000));

      expect(state().total, const Money(32000));
    });

    test('an item with nobody on it is reported, not silently dropped', () {
      controller()
        ..setMode(SplitMode.itemized)
        ..selectAll(['bea'])
        ..addItem();
      final key = state().items.single.key;
      controller().updateItem(key, (i) => i.copyWith(amount: const Money(5000)));

      expect(
        previewSplit(state(), members).failure,
        SplitFailure.itemWithoutAssignees,
      );
    });

    test('a complete itemized bill previews per person', () {
      controller()
        ..setMode(SplitMode.itemized)
        ..selectAll(['bea', 'carlo'])
        ..addItem();
      final key = state().items.single.key;
      controller().updateItem(
        key,
        (i) => i.copyWith(
          amount: const Money(10000),
          assignees: {'bea', 'carlo'},
        ),
      );

      final preview = previewSplit(state(), members);
      expect(preview.failure, isNull);
      expect(preview.result!.toJson(), {'bea': 5000, 'carlo': 5000});
    });
  });

  group('toggling participants', () {
    test('removing someone drops their input too', () {
      controller()
        ..setTotal(const Money(100000))
        ..setMode(SplitMode.exact)
        ..selectAll(['bea', 'carlo'])
        ..setInput('carlo', 40000)
        ..toggleParticipant('carlo');

      expect(state().selected, {'bea'});
      expect(state().inputs.containsKey('carlo'), isFalse);
    });
  });
}
