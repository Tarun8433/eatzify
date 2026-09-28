import 'package:dartz/dartz.dart';
import 'package:health_pro/core/errors/failures.dart';
import 'package:health_pro/domain/entities/privacy.dart';

/// docs/13 §3 and §9 — the "Privacy & data" screen's whole contract.
abstract class PrivacyRepository {
  Future<Either<Failure, PrivacyState>> load();

  /// Grant or withdraw one consent. Withdrawing is the same call with `granted: false`.
  Future<Either<Failure, List<ConsentItem>>> setConsent(String type, {required bool granted});

  /// Ask for a copy of everything. The link it returns is good for 24 hours.
  Future<Either<Failure, PrivacyRequest>> requestExport();

  /// The bundle itself, as the server sends it.
  Future<Either<Failure, Map<String, dynamic>>> exportBundle(String requestId);

  /// Ask for the account to be deleted. Seven days' cooling-off, then it runs.
  Future<Either<Failure, PrivacyRequest>> requestDeletion();

  Future<Either<Failure, Unit>> cancelDeletion();
}
