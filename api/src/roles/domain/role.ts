import { ApiProperty } from '@nestjs/swagger';
import { Allow } from 'class-validator';

// docs/20 §2 + ADR-003: Postgres only. The boilerplate's document/Mongoose branch was removed.
const idType = Number;

export class Role {
  @Allow()
  @ApiProperty({
    type: idType,
  })
  id: number | string;

  @Allow()
  @ApiProperty({
    type: String,
    example: 'admin',
  })
  name?: string;
}
