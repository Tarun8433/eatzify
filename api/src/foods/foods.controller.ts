import {
  BadRequestException,
  Body,
  Controller,
  Get,
  HttpCode,
  HttpStatus,
  Post,
  Query,
  UploadedFile,
  UseGuards,
  UseInterceptors,
} from '@nestjs/common';
import { FileInterceptor } from '@nestjs/platform-express';
import { AuthGuard } from '@nestjs/passport';
import { ApiBearerAuth, ApiBody, ApiConsumes, ApiTags } from '@nestjs/swagger';
import { FoodsService, type ImportResult } from './foods.service';
import { FOOD_GROUPS, FOOD_PREFERENCES } from './food-validation';
import { FoodEntity } from './entities/food.entity';
import { Roles } from '../roles/roles.decorator';
import { RoleEnum } from '../roles/roles.enum';
import { RolesGuard } from '../roles/roles.guard';

@ApiTags('Foods')
@ApiBearerAuth()
@Controller({ path: 'foods', version: '1' })
@UseGuards(AuthGuard('jwt'))
export class FoodsController {
  constructor(private readonly service: FoodsService) {}

  /// Admin only. Bulk data entry is an operator task, and an unguarded import endpoint is a way to
  /// write arbitrary nutrition data into every user's plan.
  @Roles(RoleEnum.admin)
  @UseGuards(RolesGuard)
  @Post('import')
  @HttpCode(HttpStatus.OK)
  @ApiConsumes('multipart/form-data')
  @ApiBody({
    schema: {
      type: 'object',
      properties: { file: { type: 'string', format: 'binary' } },
    },
  })
  @UseInterceptors(FileInterceptor('file'))
  public importCsv(
    @UploadedFile() file: Express.Multer.File,
  ): Promise<ImportResult> {
    return this.service.importCsv(file.buffer.toString('utf8'));
  }

  @Get()
  @HttpCode(HttpStatus.OK)
  public search(
    @Query('q') q?: string,
    @Query('limit') limit?: string,
    @Query('offset') offset?: string,
    @Query('suitableFor') suitableFor?: string,
    @Query('group') group?: string,
  ) {
    // Bounded rather than trusted: a client asking for 100000 rows is either a bug or an attempt,
    // and either way it is the database that pays. 20 is what the app's first page asks for.
    const take = Math.min(
      Math.max(Number.parseInt(limit ?? '', 10) || 20, 1),
      100,
    );
    const skip = Math.max(Number.parseInt(offset ?? '', 10) || 0, 0);
    // Rejected rather than ignored: a preference the vocabulary does not know is a client bug, and
    // silently returning the WHOLE table to someone who asked for vegetarian food is the one
    // failure mode this filter must not have.
    if (
      suitableFor !== undefined &&
      !(FOOD_PREFERENCES as readonly string[]).includes(suitableFor)
    ) {
      throw new BadRequestException({
        status: HttpStatus.BAD_REQUEST,
        error: {
          code: 'FOOD_PREFERENCE_INVALID',
          user_message: 'That food category is not one we know. Try another.',
        },
      });
    }

    // A comma list — the app's "Protein" chip is four groups. Rejected on an unknown name for the
    // same reason as the preference above.
    const groups = group?.split(',').filter((g) => g.length > 0);
    if (groups?.some((g) => !(FOOD_GROUPS as readonly string[]).includes(g))) {
      throw new BadRequestException({
        status: HttpStatus.BAD_REQUEST,
        error: {
          code: 'FOOD_GROUP_INVALID',
          user_message: 'That food category is not one we know. Try another.',
        },
      });
    }

    return this.service.searchWithImages(
      q ?? '',
      take,
      skip,
      suitableFor,
      groups,
    );
  }

  /// Admin only — this is what makes a food visible to every user.
  @Roles(RoleEnum.admin)
  @UseGuards(RolesGuard)
  @Post('verify')
  @HttpCode(HttpStatus.OK)
  public verify(
    @Body() body: { ids?: string[] },
  ): Promise<{ verified: number }> {
    return this.service.verify(body?.ids);
  }

  @Roles(RoleEnum.admin)
  @UseGuards(RolesGuard)
  @Get('count')
  @HttpCode(HttpStatus.OK)
  public count(): Promise<{ total: number; verified: number }> {
    return this.service.count();
  }
}
