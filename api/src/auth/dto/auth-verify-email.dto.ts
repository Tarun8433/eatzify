import { Transform } from 'class-transformer';
import { IsEmail, Matches } from 'class-validator';
import { lowerCaseTransformer } from '../../utils/transformers/lower-case.transformer';

export class AuthVerifyEmailDto {
  @Transform(lowerCaseTransformer)
  @IsEmail()
  email: string;

  @Matches(/^\d{6}$/, { message: 'code must be 6 digits' })
  code: string;
}

export class AuthResendCodeDto {
  @Transform(lowerCaseTransformer)
  @IsEmail()
  email: string;
}
