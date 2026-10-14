import { ApiProperty } from '@nestjs/swagger';
import { IsString, MinLength } from 'class-validator';

/// `POST /auth/password`: a first password for an account made with Google.
export class AuthSetPasswordDto {
  @ApiProperty()
  @IsString()
  @MinLength(8)
  password: string;
}
