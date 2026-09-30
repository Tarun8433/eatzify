import { ValidationError } from '@nestjs/common';
import { validationMessage } from '../src/utils/validation-options';

const err = (property: string) => ({ property }) as ValidationError;

describe('validationMessage', () => {
  it('should name the field a person typed', () => {
    expect(validationMessage([err('phone_e164')])).toBe(
      'Enter a valid mobile number.',
    );
    expect(validationMessage([err('dob'), err('password')])).toBe(
      'Use a password of at least 8 characters.',
    );
  });

  it('should fall back to a general sentence for other fields', () => {
    expect(validationMessage([err('dob')])).toMatch(/not valid/);
  });
});
