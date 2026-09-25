import 'package:dartz/dartz.dart';
import 'package:health_pro/core/errors/failures.dart';
import 'package:health_pro/domain/entities/app_notification.dart';

/// The reader's own messages (docs/14 §6).
abstract class NotificationsRepository {
  /// Newest first. [before] pages backwards from a message's `created_at`.
  Future<Either<Failure, NotificationFeed>> list({DateTime? before});

  Future<Either<Failure, Unit>> markRead(String id);

  Future<Either<Failure, Unit>> markAllRead();
}
