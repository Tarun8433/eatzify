import { Controller, Get, Param, Response } from '@nestjs/common';
import { ApiExcludeController } from '@nestjs/swagger';
import type { Response as ExpressResponse } from 'express';

/// The food photographs (D-83).
///
/// Its own controller, and deliberately UNAUTHENTICATED. It serves a picture of a lentil: there is
/// no health data in it, it is not scoped to a user, and every other endpoint on `FoodsController`
/// carries a class-level JWT guard that a thumbnail in a list has no way to satisfy.
///
/// The credit each image must be shown with travels with the food record, not with the file — see
/// `FoodEntity.imageAttribution`. 229 of these are CC BY or CC BY-SA and crediting the author is a
/// licence condition, not a courtesy.
@ApiExcludeController()
@Controller({ path: 'food-images', version: '1' })
export class FoodImagesController {
  @Get(':file')
  public image(
    @Param('file') file: string,
    @Response() response: ExpressResponse,
  ) {
    // `sendFile` with a root refuses to escape it, so a crafted `..` cannot walk the filesystem.
    return response.sendFile(file, { root: './files/food-images' });
  }
}
