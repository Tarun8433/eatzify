import {
  Controller,
  Get,
  NotFoundException,
  Param,
  ParseUUIDPipe,
  Query,
  Res,
} from '@nestjs/common';
import { ApiExcludeController } from '@nestjs/swagger';
import type { Response as ExpressResponse } from 'express';
import { LogsService } from './logs.service';
import { mealPhotoDir, verifyPhotoLink } from './meal-photo';

/// D-240. A diary entry's own meal photo.
///
/// No JWT guard, like the food photos — an image widget cannot send one. The SIGNATURE is the
/// permission instead: the diary hands the owner a link signed for this entry that expires within
/// the hour. Anything else is a plain 404, so the endpoint does not even confirm an entry exists.
@ApiExcludeController()
@Controller({ path: 'logs/food', version: '1' })
export class MealPhotoController {
  constructor(private readonly logs: LogsService) {}

  @Get(':id/photo')
  async photo(
    @Param('id', new ParseUUIDPipe()) id: string,
    @Query('exp') exp: string | undefined,
    @Query('sig') sig: string | undefined,
    @Res() response: ExpressResponse,
  ): Promise<void> {
    const name = verifyPhotoLink(id, exp, sig)
      ? await this.logs.photoOf(id)
      : null;
    if (!name) throw new NotFoundException();

    // Private: a shared proxy must never keep a copy of somebody's meal.
    response.setHeader('Cache-Control', 'private, max-age=3600');
    // `sendFile` with a root refuses to escape it.
    response.sendFile(name, { root: mealPhotoDir() });
  }
}
