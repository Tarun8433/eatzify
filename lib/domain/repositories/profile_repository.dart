import 'package:dartz/dartz.dart';
import 'package:health_pro/core/errors/failures.dart';
import 'package:health_pro/domain/entities/onboarding_submission.dart';
import 'package:health_pro/domain/entities/profile_view.dart';

/// docs/09 §4.
///
abstract class ProfileRepository {
  /// `POST /profile/onboarding`. The server re-runs every docs/05 §3 gate and its answer wins.
  Future<Either<Failure, OnboardingResult>> submitOnboarding(OnboardingSubmission body);

  /// `GET /profile`. `null` means onboarding was never completed — an Empty state, not a failure.
  Future<Either<Failure, ProfileView?>> profile();

  /// `PATCH /profile`. Send only what changed; the server carries the rest forward.
  Future<Either<Failure, Unit>> updateProfile(Map<String, dynamic> changed);

  /// `PATCH /profile/health`. The server re-runs the docs/05 §3 gates on the result.
  Future<Either<Failure, Unit>> updateHealth(Map<String, dynamic> changed);

  /// Uploads a profile photo and attaches it to the user. Returns the stored URL.
  Future<Either<Failure, String>> uploadPhoto(String filePath, String fileName);

  /// Removes the profile photo.
  Future<Either<Failure, Unit>> removePhoto();
}
