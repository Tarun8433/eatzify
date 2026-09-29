import { ApiProperty } from '@nestjs/swagger';
import { IsNotEmpty, MinLength } from 'class-validator';

export class AuthResetPasswordDto {
  @ApiProperty()
  @MinLength(8)
  password: string;

  @ApiProperty()
  @IsNotEmpty()
  hash: string;
}
