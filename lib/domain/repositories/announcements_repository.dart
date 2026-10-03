import 'package:dartz/dartz.dart';
import 'package:health_pro/core/errors/failures.dart';
import 'package:health_pro/domain/entities/announcement.dart';

/// `GET /announcements`: what the team wants this person to see now, most urgent first.
// ignore: one_member_abstracts
abstract class AnnouncementsRepository {
  Future<Either<Failure, List<Announcement>>> active();
}
