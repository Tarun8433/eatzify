import 'package:dartz/dartz.dart';
import 'package:health_pro/core/errors/failures.dart';
import 'package:health_pro/domain/entities/support_ticket.dart';

/// The reader's own support conversations (docs/14 §6).
abstract class TicketsRepository {
  /// Most recently touched first.
  Future<Either<Failure, List<SupportTicket>>> list();

  /// Starts one. [requestId] is the `X-Request-Id` of whatever went wrong, when there is one.
  Future<Either<Failure, SupportTicket>> open({
    required String subject,
    required String body,
    String? requestId,
  });

  Future<Either<Failure, SupportThread>> thread(String id);

  Future<Either<Failure, Unit>> reply(String id, String body);
}
