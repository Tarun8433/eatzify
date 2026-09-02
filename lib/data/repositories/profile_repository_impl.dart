import 'package:dartz/dartz.dart';
import 'package:health_pro/core/errors/failures.dart';
import 'package:health_pro/data/datasources/remote/profile_remote_data_source.dart';
import 'package:health_pro/domain/entities/onboarding_submission.dart';
import 'package:health_pro/domain/entities/profile_view.dart';
import 'package:health_pro/domain/repositories/profile_repository.dart';

class ProfileRepositoryImpl implements ProfileRepository {
  const ProfileRepositoryImpl(this._remote);

  final ProfileRemoteDataSource _remote;

  @override
  Future<Either<Failure, OnboardingResult>> submitOnboarding(OnboardingSubmission body) =>
      _remote.submitOnboarding(body);

  @override
  Future<Either<Failure, ProfileView?>> profile() => _remote.profile();

  @override
  Future<Either<Failure, Unit>> updateProfile(Map<String, dynamic> changed) =>
      _remote.patch('/profile', changed);

  @override
  Future<Either<Failure, Unit>> updateHealth(Map<String, dynamic> changed) =>
      _remote.patch('/profile/health', changed);

  @override
  Future<Either<Failure, String>> uploadPhoto(String filePath, String fileName) =>
      _remote.uploadPhoto(filePath, fileName);

  @override
  Future<Either<Failure, Unit>> removePhoto() => _remote.removePhoto();
}
