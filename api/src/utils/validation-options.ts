import {
  HttpStatus,
  UnprocessableEntityException,
  ValidationError,
  ValidationPipeOptions,
} from '@nestjs/common';

type ValidationErrorsTree = {
  [key: string]: string | ValidationErrorsTree;
};

function generateErrors(errors: ValidationError[]): ValidationErrorsTree {
  return errors.reduce<ValidationErrorsTree>(
    (accumulator, currentValue) => ({
      ...accumulator,
      [currentValue.property]:
        (currentValue.children?.length ?? 0) > 0
          ? generateErrors(currentValue.children ?? [])
          : Object.values(currentValue.constraints ?? {}).join(', '),
    }),
    {},
  );
}

/// Plain words for the fields a person types; anything else gets the general sentence.
const FIELD_MESSAGES: Record<string, string> = {
  email: 'Enter a valid email address.',
  password: 'Use a password of at least 8 characters.',
  phone_e164: 'Enter a valid mobile number.',
  code: 'Enter the 6-digit code from the email.',
};

export function validationMessage(errors: ValidationError[]): string {
  const field = errors.find((e) => FIELD_MESSAGES[e.property])?.property;
  return field
    ? FIELD_MESSAGES[field]
    : 'Some details are not valid. Check them and try again.';
}

const validationOptions: ValidationPipeOptions = {
  transform: true,
  whitelist: true,
  errorHttpStatusCode: HttpStatus.UNPROCESSABLE_ENTITY,
  exceptionFactory: (errors: ValidationError[]) => {
    return new UnprocessableEntityException({
      status: HttpStatus.UNPROCESSABLE_ENTITY,
      // The app shows only `error.user_message` (app rule 7); without one every rejected form
      // read "Something went wrong". `errors` stays for anything reading fields.
      error: {
        code: 'VALIDATION_FAILED',
        user_message: validationMessage(errors),
      },
      errors: generateErrors(errors),
    });
  },
};

export default validationOptions;
