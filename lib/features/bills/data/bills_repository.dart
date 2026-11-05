import 'dart:io' show SocketException;

import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/money/money.dart';
import '../../../core/split/split.dart';
import '../../../core/supabase/supabase_providers.dart';
import '../domain/bill_failure.dart';
import '../domain/bill_models.dart';

part 'bills_repository.g.dart';

/// The payload `create_bill` and `update_bill` take (spec §7).
///
/// Built once here so the create and edit paths cannot describe a bill
/// differently.
class BillDraft {
  const BillDraft({
    required this.groupId,
    required this.title,
    required this.total,
    required this.paidBy,
    required this.mode,
    required this.participants,
    required this.billDate,
    this.notes,
    this.category,
    this.items = const <SplitItem>[],
    this.extras = ItemizedExtras.none,
    this.attachmentPaths = const <String>[],
  });

  final String groupId;
  final String title;
  final Money total;
  final String paidBy;
  final SplitMode mode;

  /// Canonically ordered — see `canonicalParticipantOrder` (DECISIONS D-31).
  final List<SplitParticipant> participants;

  final DateTime billDate;
  final String? notes;
  final String? category;
  final List<SplitItem> items;
  final ItemizedExtras extras;
  final List<String> attachmentPaths;

  Map<String, dynamic> toPayload() => {
        'group_id': groupId,
        'title': title,
        'total_amount': total.centavos,
        'paid_by': paidBy,
        'split_mode': mode.name,
        'bill_date': billDate.toIso8601String().split('T').first,
        if (notes != null && notes!.isNotEmpty) 'notes': notes,
        if (category != null && category!.isNotEmpty) 'category': category,
        'participants': [
          for (final p in participants)
            {'user_id': p.userId, if (p.input != null) 'input': p.input},
        ],
        if (mode == SplitMode.itemized) ...{
          'items': [
            for (final item in items)
              {
                'name': item.name,
                'amount': item.amount.centavos,
                'assignees': item.assignees,
              },
          ],
          'extras': {
            'service_charge': extras.serviceCharge.centavos,
            'tax': extras.tax.centavos,
            'discount': extras.discount.centavos,
          },
        },
        if (attachmentPaths.isNotEmpty) 'attachment_paths': attachmentPaths,
      };

  /// The same request the local preview runs through [SplitEngine], so what
  /// the form shows is what the server will compute.
  SplitRequest toSplitRequest() => SplitRequest(
        total: total,
        mode: mode,
        participants: participants,
        items: items,
        extras: extras,
      );
}

abstract interface class BillsRepository {
  Future<List<Bill>> billsForGroup(String groupId);

  Future<Bill> bill(String billId);

  Future<String> createBill(BillDraft draft);

  Future<void> updateBill(String billId, BillDraft draft);

  Future<void> voidBill(String billId, {String? reason});

  Future<List<GroupBalance>> myBalances();

  Future<List<OpenShare>> myOpenShares();

  /// Records receipts already uploaded to storage (spec §12.11: at most five
  /// per bill). RLS lets a member insert these directly.
  Future<void> addAttachments({
    required String billId,
    required List<String> paths,
  });

  Future<void> removeAttachment(String attachmentId);
}

class SupabaseBillsRepository implements BillsRepository {
  SupabaseBillsRepository(this._client);

  final SupabaseClient _client;

  /// Bills, shares, items and attachments in one round trip. RLS decides which
  /// bills come back; there is no group filter to get wrong.
  static const String _billSelect = '''
    id, group_id, title, notes, category, total_amount, paid_by, created_by,
    split_mode, bill_date, status, itemized_extras, created_at,
    receive_method_id,
    bill_shares(id, user_id, amount, status, settled_at, last_reminded_at),
    bill_items(id, name, amount, position, bill_item_assignees(user_id)),
    bill_attachments(id, path, uploaded_by)
  ''';

  @override
  Future<List<Bill>> billsForGroup(String groupId) {
    return _guard(() async {
      final rows = await _client
          .from('bills')
          .select(_billSelect)
          .eq('group_id', groupId)
          .order('bill_date', ascending: false)
          .order('created_at', ascending: false);

      return rows.map(_toBill).toList(growable: false);
    });
  }

  @override
  Future<Bill> bill(String billId) {
    return _guard(() async {
      final row =
          await _client.from('bills').select(_billSelect).eq('id', billId).single();
      return _toBill(row);
    });
  }

  static Bill _toBill(Map<String, dynamic> row) {
    final items = ((row['bill_items'] as List<dynamic>?) ?? const [])
        .cast<Map<String, dynamic>>()
        .map((item) => BillItemRow(
              id: item['id'] as String,
              name: item['name'] as String,
              amount: Money((item['amount'] as num).toInt()),
              position: (item['position'] as num?)?.toInt(),
              assignees: ((item['bill_item_assignees'] as List<dynamic>?) ??
                      const [])
                  .cast<Map<String, dynamic>>()
                  .map((a) => a['user_id'] as String)
                  .toList(growable: false),
            ))
        .toList()
      ..sort((a, b) => (a.position ?? 0).compareTo(b.position ?? 0));

    return Bill(
      id: row['id'] as String,
      groupId: row['group_id'] as String,
      title: row['title'] as String,
      notes: row['notes'] as String?,
      category: row['category'] as String?,
      totalAmount: Money((row['total_amount'] as num).toInt()),
      paidBy: row['paid_by'] as String,
      createdBy: row['created_by'] as String,
      splitMode: row['split_mode'] as String,
      billDate: DateTime.parse(row['bill_date'] as String),
      status: row['status'] as String,
      receiveMethodId: row['receive_method_id'] as String?,
      createdAt: DateTime.tryParse(row['created_at'] as String? ?? ''),
      extras: ItemizedExtrasJson.fromJson(
        (row['itemized_extras'] as Map<String, dynamic>?) ?? const {},
      ),
      shares: ((row['bill_shares'] as List<dynamic>?) ?? const [])
          .cast<Map<String, dynamic>>()
          .map(BillShare.fromJson)
          .toList(growable: false),
      items: items,
      attachments: ((row['bill_attachments'] as List<dynamic>?) ?? const [])
          .cast<Map<String, dynamic>>()
          .map(BillAttachment.fromJson)
          .toList(growable: false),
    );
  }

  @override
  Future<String> createBill(BillDraft draft) {
    return _guard(
      () => _client.rpc<String>(
        'create_bill',
        params: {'p_payload': draft.toPayload()},
      ),
    );
  }

  @override
  Future<void> updateBill(String billId, BillDraft draft) {
    return _guard(
      () => _client.rpc<void>(
        'update_bill',
        params: {'p_bill_id': billId, 'p_payload': draft.toPayload()},
      ),
    );
  }

  @override
  Future<void> voidBill(String billId, {String? reason}) {
    return _guard(
      () => _client.rpc<void>(
        'void_bill',
        params: {'p_bill_id': billId, 'p_reason': reason},
      ),
    );
  }

  @override
  Future<List<GroupBalance>> myBalances() {
    return _guard(() async {
      final rows = await _client.rpc<List<dynamic>>('get_my_balances');
      return rows
          .cast<Map<String, dynamic>>()
          .map(GroupBalance.fromJson)
          .toList(growable: false);
    });
  }

  @override
  Future<List<OpenShare>> myOpenShares() {
    return _guard(() async {
      final rows = await _client.rpc<List<dynamic>>('get_my_open_shares');
      return rows
          .cast<Map<String, dynamic>>()
          .map(OpenShare.fromJson)
          .toList(growable: false);
    });
  }

  @override
  Future<void> addAttachments({
    required String billId,
    required List<String> paths,
  }) {
    return _guard(() async {
      if (paths.isEmpty) return;
      final userId = _client.auth.currentUser?.id;
      await _client.from('bill_attachments').insert([
        for (final path in paths)
          {'bill_id': billId, 'path': path, 'uploaded_by': userId},
      ]);
    });
  }

  @override
  Future<void> removeAttachment(String attachmentId) => _guard(
        () => _client.from('bill_attachments').delete().eq('id', attachmentId),
      );

  static Future<T> _guard<T>(Future<T> Function() action) async {
    try {
      return await action();
    } on PostgrestException catch (error) {
      throw BillFailure.fromCode(error.code, error.message);
    } on SocketException catch (_) {
      throw const BillFailure(
        BillFailureKind.network,
        "Can't reach Hati right now.",
      );
    }
  }
}

@Riverpod(keepAlive: true)
BillsRepository billsRepository(Ref ref) {
  if (!ref.watch(isBackendConfiguredProvider)) {
    throw StateError('Bills need a Supabase project; see ConfigMissingScreen.');
  }
  return SupabaseBillsRepository(Supabase.instance.client);
}
