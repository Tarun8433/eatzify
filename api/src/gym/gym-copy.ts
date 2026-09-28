import {
  ConflictException,
  ForbiddenException,
  HttpStatus,
  NotFoundException,
  UnprocessableEntityException,
} from '@nestjs/common';

/// Every sentence the Gym routes can put in front of a user. The app shows `user_message` verbatim
/// (CLAUDE.md rule 7), so the wording lives here, once, like plans/plan-copy.ts.

export const GYM_COPY = {
  exerciseNotFound: 'That exercise could not be found.',
  exerciseExists: 'You already have an exercise with that name.',
  exerciseNotYours: 'Only exercises you created can be changed.',
  routineNotFound: 'That routine could not be found. Pull down to refresh.',
  workoutNotFound: 'That workout could not be found.',
  unknownExercise:
    'This workout names an exercise that no longer exists. Remove it and try again.',
  badSpan: 'A workout has to end after it starts.',
  tooLong:
    'A workout cannot run longer than a day. Check the start and end times.',
  badDate: 'That day is not one you can plan.',
  badSchedule: 'The weekly schedule names a routine that does not exist.',
  badMonth: 'That month is not valid.',
  modeMismatch: 'Cardio exercises are logged by time and speed.',
} as const;

const body = (status: HttpStatus, code: string, userMessage: string) => ({
  status,
  error: { code, user_message: userMessage },
});

export const gymNotFound = (code: string, message: string) =>
  new NotFoundException(body(HttpStatus.NOT_FOUND, code, message));

export const gymInvalid = (message: string) =>
  new UnprocessableEntityException(
    body(HttpStatus.UNPROCESSABLE_ENTITY, 'GYM_INVALID', message),
  );

export const gymConflict = (message: string) =>
  new ConflictException(
    body(HttpStatus.CONFLICT, 'GYM_EXERCISE_EXISTS', message),
  );

export const gymForbidden = (message: string) =>
  new ForbiddenException(body(HttpStatus.FORBIDDEN, 'GYM_NOT_OWNER', message));
