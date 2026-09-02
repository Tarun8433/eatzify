import { ApiProperty } from '@nestjs/swagger';
import { IsOptional, IsString, Matches } from 'class-validator';

export class AuthOtpVerifyDto {
  @ApiProperty({ example: '+919999999999' })
  @IsString()
  @Matches(/^\+[1-9]\d{7,14}$/, {
    message: 'must be E.164, e.g. +919999999999',
  })
  phone_e164: string;

  @ApiProperty({ example: '000000' })
  @IsString()
  @Matches(/^\d{6}$/, { message: 'must be 6 digits' })
  otp: string;

  @ApiProperty({ example: 'ios-abc123', required: false })
  @IsOptional()
  @IsString()
  device?: string;
}
