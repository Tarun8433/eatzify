import { ApiProperty } from '@nestjs/swagger';
import { IsNotEmpty, IsOptional, IsString } from 'class-validator';

export class AuthGoogleLoginDto {
  @ApiProperty({ description: 'Google ID token from the app' })
  @IsString()
  @IsNotEmpty()
  id_token: string;

  /// Sent by the app; sessions are not per-device yet, so it is accepted and unused.
  @ApiProperty({ required: false })
  @IsString()
  @IsOptional()
  device?: string;
}
