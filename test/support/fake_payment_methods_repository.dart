import 'package:hati/features/profile/data/payment_methods_repository.dart';
import 'package:hati/features/profile/domain/payment_method.dart';

/// An in-memory [PaymentMethodsRepository] for tests.
class FakePaymentMethodsRepository implements PaymentMethodsRepository {
  FakePaymentMethodsRepository({List<PaymentMethod>? methods})
    : methods = methods ?? <PaymentMethod>[];

  final List<PaymentMethod> methods;

  /// userId → preferred method id (D-66).
  final Map<String, String?> preferred = <String, String?>{};

  PaymentMethodFailure? failWith;
  final List<String> calls = <String>[];

  @override
  Future<List<PaymentMethod>> forUser(String userId) async {
    calls.add('forUser');
    _maybeFail();
    return methods.where((m) => m.userId == userId).toList();
  }

  @override
  Future<void> save(PaymentMethod method) async {
    calls.add('save');
    _maybeFail();
    methods.add(method);
  }

  @override
  Future<void> remove(String id) async {
    calls.add('remove');
    _maybeFail();
    methods.removeWhere((m) => m.id == id);
  }

  @override
  Future<void> makeDefault({required String userId, required String id}) async {
    calls.add('makeDefault');
    _maybeFail();
  }

  @override
  Future<String?> preferredFor(String userId) async {
    calls.add('preferredFor');
    _maybeFail();
    return preferred[userId];
  }

  @override
  Future<void> setPreferred({required String userId, String? methodId}) async {
    calls.add('setPreferred');
    _maybeFail();
    preferred[userId] = methodId;
  }

  void _maybeFail() {
    final failure = failWith;
    if (failure != null) {
      failWith = null;
      throw failure;
    }
  }
}
