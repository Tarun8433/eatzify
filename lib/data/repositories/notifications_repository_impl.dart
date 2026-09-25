import 'package:dartz/dartz.dart';
import 'package:health_pro/core/errors/failures.dart';
import 'package:health_pro/data/datasources/remote/notifications_remote_data_source.dart';
import 'package:health_pro/domain/entities/app_notification.dart';
import 'package:health_pro/domain/repositories/notifications_repository.dart';

class NotificationsRepositoryImpl implements NotificationsRepository {
  const NotificationsRepositoryImpl(this._remote);

  final NotificationsRemoteDataSource _remote;

  @override
  Future<Either<Failure, NotificationFeed>> list({DateTime? before}) =>
      _remote.list(before: before);

  @override
  Future<Either<Failure, Unit>> markRead(String id) => _remote.markRead(id);

  @override
  Future<Either<Failure, Unit>> markAllRead() => _remote.markAllRead();
}
