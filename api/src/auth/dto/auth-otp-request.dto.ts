import { ApiProperty } from '@nestjs/swagger';
import { IsString, Matches } from 'class-validator';

export class AuthOtpRequestDto {
  @ApiProperty({ example: '+919999999999' })
  @IsString()
  @Matches(/^\+[1-9]\d{7,14}$/, {
    message: 'must be E.164, e.g. +919999999999',
  })
  phone_e164: string;
}
