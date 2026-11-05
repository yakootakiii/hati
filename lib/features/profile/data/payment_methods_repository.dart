import 'dart:io' show SocketException;

import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/supabase/supabase_providers.dart';
import '../domain/payment_method.dart';

part 'payment_methods_repository.g.dart';

/// Payment methods are one of the few tables clients write directly: RLS lets
/// you edit your own and read those of anyone you share a group with (§5.4).
abstract interface class PaymentMethodsRepository {
  Future<List<PaymentMethod>> forUser(String userId);

  Future<void> save(PaymentMethod method);

  Future<void> remove(String id);

  /// Makes one method the default, clearing the flag from the others.
  Future<void> makeDefault({required String userId, required String id});

  /// Where this person asks to be paid unless a bill says otherwise — one of
  /// their methods, or null for any of them (DECISIONS D-66).
  Future<String?> preferredFor(String userId);

  Future<void> setPreferred({required String userId, String? methodId});
}

class SupabasePaymentMethodsRepository implements PaymentMethodsRepository {
  SupabasePaymentMethodsRepository(this._client);

  final SupabaseClient _client;

  @override
  Future<List<PaymentMethod>> forUser(String userId) {
    return _guard(() async {
      final rows = await _client
          .from('payment_methods')
          .select()
          .eq('user_id', userId)
          .order('is_default', ascending: false)
          .order('created_at');
      return rows.map(PaymentMethod.fromJson).toList(growable: false);
    });
  }

  @override
  Future<void> save(PaymentMethod method) {
    return _guard(() async {
      final row = {
        'user_id': method.userId,
        'type': method.type,
        'label': method.label,
        'account_name': method.accountName,
        'account_number': method.accountNumber,
        'qr_image_path': method.qrImagePath,
        'is_default': method.isDefault,
      };

      if (method.id.isEmpty) {
        await _client.from('payment_methods').insert(row);
      } else {
        await _client.from('payment_methods').update(row).eq('id', method.id);
      }
    });
  }

  @override
  Future<void> remove(String id) => _guard(
        () => _client.from('payment_methods').delete().eq('id', id),
      );

  @override
  Future<void> makeDefault({required String userId, required String id}) {
    return _guard(() async {
      // A partial unique index allows only one default per user, so the old
      // one has to go first.
      await _client
          .from('payment_methods')
          .update({'is_default': false})
          .eq('user_id', userId)
          .eq('is_default', true);
      await _client
          .from('payment_methods')
          .update({'is_default': true})
          .eq('id', id);
    });
  }

  @override
  Future<String?> preferredFor(String userId) {
    return _guard(() async {
      final row = await _client
          .from('profiles')
          .select('receive_method_id')
          .eq('id', userId)
          .maybeSingle();
      return row?['receive_method_id'] as String?;
    });
  }

  @override
  Future<void> setPreferred({required String userId, String? methodId}) {
    return _guard(
      () => _client
          .from('profiles')
          .update({'receive_method_id': methodId})
          .eq('id', userId),
    );
  }

  static Future<T> _guard<T>(Future<T> Function() action) async {
    try {
      return await action();
    } on PostgrestException catch (error) {
      throw PaymentMethodFailure(error.message);
    } on SocketException catch (_) {
      throw const PaymentMethodFailure("Can't reach Hati right now.");
    }
  }
}

class PaymentMethodFailure implements Exception {
  const PaymentMethodFailure(this.message);

  final String message;

  @override
  String toString() => 'PaymentMethodFailure: $message';
}

@Riverpod(keepAlive: true)
PaymentMethodsRepository paymentMethodsRepository(Ref ref) {
  if (!ref.watch(isBackendConfiguredProvider)) {
    throw StateError('Payment methods need a Supabase project.');
  }
  return SupabasePaymentMethodsRepository(Supabase.instance.client);
}

@riverpod
Future<List<PaymentMethod>> paymentMethodsFor(Ref ref, String userId) =>
    ref.watch(paymentMethodsRepositoryProvider).forUser(userId);

@riverpod
Future<String?> preferredReceiveMethod(Ref ref, String userId) =>
    ref.watch(paymentMethodsRepositoryProvider).preferredFor(userId);

@Riverpod(keepAlive: true)
class PaymentMethodActions extends _$PaymentMethodActions {
  @override
  FutureOr<void> build() {}

  Future<bool> save(PaymentMethod method) => _run(method.userId, () =>
      ref.read(paymentMethodsRepositoryProvider).save(method));

  Future<bool> remove({required String userId, required String id}) =>
      _run(userId, () => ref.read(paymentMethodsRepositoryProvider).remove(id));

  Future<bool> makeDefault({required String userId, required String id}) =>
      _run(
        userId,
        () => ref
            .read(paymentMethodsRepositoryProvider)
            .makeDefault(userId: userId, id: id),
      );

  Future<bool> setPreferred({required String userId, String? methodId}) =>
      _run(
        userId,
        () => ref
            .read(paymentMethodsRepositoryProvider)
            .setPreferred(userId: userId, methodId: methodId),
      );

  Future<bool> _run(String userId, Future<void> Function() action) async {
    state = const AsyncValue<void>.loading();
    try {
      await action();
      ref
        ..invalidate(paymentMethodsForProvider(userId))
        ..invalidate(preferredReceiveMethodProvider(userId));
      state = const AsyncValue<void>.data(null);
      return true;
    } on PaymentMethodFailure catch (failure, stackTrace) {
      state = AsyncValue<void>.error(failure, stackTrace);
      return false;
    }
  }
}
