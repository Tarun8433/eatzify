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
