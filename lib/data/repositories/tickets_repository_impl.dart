import 'package:dartz/dartz.dart';
import 'package:health_pro/core/errors/failures.dart';
import 'package:health_pro/data/datasources/remote/tickets_remote_data_source.dart';
import 'package:health_pro/domain/entities/support_ticket.dart';
import 'package:health_pro/domain/repositories/tickets_repository.dart';

class TicketsRepositoryImpl implements TicketsRepository {
  const TicketsRepositoryImpl(this._remote);

  final TicketsRemoteDataSource _remote;

  @override
  Future<Either<Failure, List<SupportTicket>>> list() => _remote.list();

  @override
  Future<Either<Failure, SupportTicket>> open({
    required String subject,
    required String body,
    String? requestId,
  }) => _remote.open(subject: subject, body: body, requestId: requestId);

  @override
  Future<Either<Failure, SupportThread>> thread(String id) => _remote.thread(id);

  @override
  Future<Either<Failure, Unit>> reply(String id, String body) => _remote.reply(id, body);
}
