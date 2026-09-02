import { ApiPropertyOptional } from '@nestjs/swagger';
import { IsIn, IsOptional } from 'class-validator';

export class GeneratePlanDto {
  @ApiPropertyOptional({ example: 'user_request' })
  @IsOptional()
  @IsIn(['user_request', 'profile_changed', 'scheduled', 'coach_request'])
  regenerate_reason?: string;
}
