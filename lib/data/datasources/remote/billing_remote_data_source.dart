import 'package:dartz/dartz.dart';
import 'package:dio/dio.dart';
import 'package:health_pro/core/errors/failures.dart';
import 'package:health_pro/core/network/error_mapper.dart';
import 'package:health_pro/domain/entities/billing.dart';

class BillingRemoteDataSource {
  BillingRemoteDataSource(this._dio);

  final Dio _dio;

  Future<Either<Failure, Entitlements>> entitlements() async {
    try {
      final res = await _dio.get<Map<String, dynamic>>('/billing/entitlements');
      return Right(Entitlements.fromJson(res.data ?? const {}));
    } on DioException catch (e) {
      return Left(mapDioError(e));
    }
  }

  /// `POST /billing/checkout` (D-194). Sends a CELL of the price matrix, never an amount.
  ///
  /// [idempotencyKey] belongs to one attempt, so a network-level retry of that attempt returns the
  /// order it already opened instead of opening a second one.
  Future<Either<Failure, CheckoutSession>> checkout({
    required String tier,
    required int months,
    required String idempotencyKey,
    String? couponCode,
  }) async {
    try {
      final res = await _dio.post<Map<String, dynamic>>(
        '/billing/checkout',
        data: {
          'tier': tier,
          'duration': '${months}M',
          if (couponCode != null && couponCode.isNotEmpty) 'coupon_code': couponCode,
        },
        options: Options(headers: {'Idempotency-Key': idempotencyKey}),
      );
      return Right(CheckoutSession.fromJson(res.data ?? const {}));
    } on DioException catch (e) {
      return Left(mapDioError(e));
    }
  }

  /// `GET /billing/subscription` (docs/09 §7).
  Future<Either<Failure, SubscriptionState>> subscription() =>
      _state(() => _dio.get<Map<String, dynamic>>('/billing/subscription'));

  /// `POST /billing/trial` (docs/11 §6).
  Future<Either<Failure, SubscriptionState>> startTrial(String tier) =>
      _state(() => _dio.post<Map<String, dynamic>>('/billing/trial', data: {'tier': tier}));

  /// `POST /billing/cancel` — stops the renewal, keeps the access (docs/09 §7).
  Future<Either<Failure, SubscriptionState>> cancelRenewal({String? reason}) => _state(
    () => _dio.post<Map<String, dynamic>>(
      '/billing/cancel',
      data: {if (reason != null && reason.isNotEmpty) 'reason': reason},
    ),
  );

  /// `POST /billing/upgrade/quote` — docs/11 §7's arithmetic, before anything is charged.
  Future<Either<Failure, UpgradeQuote>> upgradeQuote({
    required String tier,
    required int months,
  }) async {
    try {
      final res = await _dio.post<Map<String, dynamic>>(
        '/billing/upgrade/quote',
        data: {'tier': tier, 'duration': '${months}M'},
      );
      return Right(UpgradeQuote.fromJson(res.data ?? const {}));
    } on DioException catch (e) {
      return Left(mapDioError(e));
    }
  }

  /// `POST /billing/upgrade` — an order for the difference only.
  Future<Either<Failure, CheckoutSession>> upgrade({
    required String tier,
    required int months,
    required String idempotencyKey,
  }) async {
    try {
      final res = await _dio.post<Map<String, dynamic>>(
        '/billing/upgrade',
        data: {'tier': tier, 'duration': '${months}M'},
        options: Options(headers: {'Idempotency-Key': idempotencyKey}),
      );
      return Right(CheckoutSession.fromJson(res.data ?? const {}));
    } on DioException catch (e) {
      return Left(mapDioError(e));
    }
  }

  Future<Either<Failure, SubscriptionState>> _state(
    Future<Response<Map<String, dynamic>>> Function() send,
  ) async {
    try {
      final res = await send();
      return Right(SubscriptionState.fromJson(res.data ?? const {}));
    } on DioException catch (e) {
      return Left(mapDioError(e));
    }
  }

  /// Stub builds only. The server refuses this outside stub mode, so the app does not have to be
  /// the thing that remembers — but it never offers it either (D-194).
  Future<Either<Failure, Unit>> completeStubPayment(String orderId) async {
    try {
      await _dio.post<void>('/billing/checkout/simulate', data: {'order_id': orderId});
      return const Right(unit);
    } on DioException catch (e) {
      return Left(mapDioError(e));
    }
  }

  /// `GET /billing/prices` returns { TIER: { '1M': paise, ... } } — flattened here so a screen
  /// iterates rows instead of re-walking the server's matrix shape.
  Future<Either<Failure, List<TierPrice>>> prices() async {
    try {
      final res = await _dio.get<Map<String, dynamic>>('/billing/prices');
      final rows = <TierPrice>[];
      for (final MapEntry(key: tier, value: durations) in (res.data ?? const {}).entries) {
        if (durations is! Map<String, dynamic>) continue;
        for (final MapEntry(key: duration, value: paise) in durations.entries) {
          final months = int.tryParse(duration.replaceAll('M', ''));
          if (months == null || paise is! num) continue;
          rows.add(TierPrice(tier: tier, months: months, pricePaise: paise.toInt()));
        }
      }
      rows.sort((a, b) {
        final byTier = a.tier.compareTo(b.tier);
        return byTier != 0 ? byTier : a.months.compareTo(b.months);
      });
      return Right(rows);
    } on DioException catch (e) {
      return Left(mapDioError(e));
    }
  }
}
