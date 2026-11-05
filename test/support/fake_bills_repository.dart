import 'package:hati/core/money/money.dart';
import 'package:hati/features/bills/data/bills_repository.dart';
import 'package:hati/features/bills/domain/bill_failure.dart';
import 'package:hati/features/bills/domain/bill_models.dart';

/// An in-memory [BillsRepository] for tests.
class FakeBillsRepository implements BillsRepository {
  FakeBillsRepository({
    List<Bill>? bills,
    List<GroupBalance>? balances,
    List<OpenShare>? openShares,
  }) : bills = bills ?? <Bill>[],
       balances = balances ?? <GroupBalance>[],
       openShares = openShares ?? <OpenShare>[];

  final List<Bill> bills;
  final List<GroupBalance> balances;
  final List<OpenShare> openShares;

  BillFailure? failWith;
  final List<String> calls = <String>[];
  BillDraft? lastDraft;
  String? lastBillId;
  String? lastReason;

  @override
  Future<List<Bill>> billsForGroup(String groupId) async {
    calls.add('billsForGroup');
    _maybeFail();
    return bills.where((b) => b.groupId == groupId).toList();
  }

  @override
  Future<Bill> bill(String billId) async {
    calls.add('bill');
    _maybeFail();
    return bills.firstWhere((b) => b.id == billId);
  }

  @override
  Future<String> createBill(BillDraft draft) async {
    calls.add('createBill');
    lastDraft = draft;
    _maybeFail();
    return 'new-bill-id';
  }

  @override
  Future<void> updateBill(String billId, BillDraft draft) async {
    calls.add('updateBill');
    lastBillId = billId;
    lastDraft = draft;
    _maybeFail();
  }

  @override
  Future<void> voidBill(String billId, {String? reason}) async {
    calls.add('voidBill');
    lastBillId = billId;
    lastReason = reason;
    _maybeFail();
  }

  @override
  Future<List<GroupBalance>> myBalances() async {
    calls.add('myBalances');
    _maybeFail();
    return balances;
  }

  @override
  Future<List<OpenShare>> myOpenShares() async {
    calls.add('myOpenShares');
    _maybeFail();
    return openShares;
  }

  final List<String> attachedPaths = <String>[];
  String? lastRemovedAttachmentId;

  @override
  Future<void> addAttachments({
    required String billId,
    required List<String> paths,
  }) async {
    calls.add('addAttachments');
    lastBillId = billId;
    attachedPaths.addAll(paths);
    _maybeFail();
  }

  @override
  Future<void> removeAttachment(String attachmentId) async {
    calls.add('removeAttachment');
    lastRemovedAttachmentId = attachmentId;
    _maybeFail();
  }

  void _maybeFail() {
    final failure = failWith;
    if (failure != null) {
      failWith = null;
      throw failure;
    }
  }
}

/// A bill fixture matching the §1 reference scenario.
Bill airbnbBill({
  String id = 'bill-1',
  String groupId = 'g1',
  String paidBy = 'bea',
  String status = 'open',
  List<BillShare>? shares,
}) {
  return Bill(
    id: id,
    groupId: groupId,
    title: 'Airbnb – 2 nights',
    totalAmount: const Money(1250000),
    paidBy: paidBy,
    createdBy: paidBy,
    splitMode: 'equal',
    billDate: DateTime.utc(2026, 9, 20),
    status: status,
    shares:
        shares ??
        const [
          BillShare(
            id: 's1',
            userId: 'bea',
            amount: Money(312500),
            status: 'settled',
          ),
          BillShare(
            id: 's2',
            userId: 'carlo',
            amount: Money(312500),
            status: 'unpaid',
          ),
          BillShare(
            id: 's3',
            userId: 'dana',
            amount: Money(312500),
            status: 'unpaid',
          ),
          BillShare(
            id: 's4',
            userId: 'eli',
            amount: Money(312500),
            status: 'unpaid',
          ),
        ],
  );
}
