import {
  HttpStatus,
  Injectable,
  UnprocessableEntityException,
} from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import { DataSource, ILike, Repository } from 'typeorm';
import { parse } from 'csv-parse/sync';
import { FoodEntity } from './entities/food.entity';
import { HouseholdMeasureEntity } from './entities/household-measure.entity';
import { unknownColumns, validateRow, type RowError } from './food-validation';

export type ImportResult = {
  imported: number;
  updated: number;
  skipped: number;
  errors: RowError[];
};

@Injectable()
export class FoodsService {
  constructor(
    @InjectRepository(FoodEntity)
    private readonly foods: Repository<FoodEntity>,
    private readonly dataSource: DataSource,
  ) {}

  /// Imports a CSV. Rows are validated first and the whole import is refused if any row fails —
  /// a partial import leaves the operator guessing which half landed, and a food database that is
  /// silently 80 % correct is worse than one that is obviously empty.
  async importCsv(csv: string): Promise<ImportResult> {
    let rows: Record<string, string>[];
    try {
      rows = parse(csv, { columns: true, skip_empty_lines: true, trim: true });
    } catch (e) {
      throw new UnprocessableEntityException({
        status: HttpStatus.UNPROCESSABLE_ENTITY,
        error: {
          code: 'CSV_UNREADABLE',
          user_message: `That file could not be read as CSV: ${(e as Error).message}`,
        },
      });
    }

    const unknown = unknownColumns(Object.keys(rows[0] ?? {}));
    if (unknown.length > 0) {
      throw new UnprocessableEntityException({
        status: HttpStatus.UNPROCESSABLE_ENTITY,
        error: {
          code: 'CSV_UNKNOWN_COLUMN',
          user_message:
            `Unrecognised column(s): ${unknown.join(', ')}. Nothing was imported — a column the ` +
            `importer does not know would be silently dropped.`,
        },
      });
    }

    const errors: RowError[] = [];
    const valid: ReturnType<typeof validateRow>['food'][] = [];

    rows.forEach((raw, i) => {
      // +2: a spreadsheet's row 1 is the header, so row 2 is the first record the operator sees.
      const { food, errors: rowErrors } = validateRow(raw, i + 2);
      errors.push(...rowErrors);
      if (food) valid.push(food);
    });

    if (errors.length > 0) {
      throw new UnprocessableEntityException({
        status: HttpStatus.UNPROCESSABLE_ENTITY,
        error: {
          code: 'CSV_INVALID',
          user_message: `${errors.length} problem(s) found. Nothing was imported — fix the rows below and upload again.`,
          details: { errors: errors.slice(0, 100) },
        },
      });
    }

    let imported = 0;
    let updated = 0;

    await this.dataSource.transaction(async (manager) => {
      for (const food of valid) {
        if (!food) continue;

        const existing = await manager.findOne(FoodEntity, {
          where: { name: food.name },
        });
        const saved = await manager.save(FoodEntity, {
          ...(existing ?? {}),
          name: food.name,
          nameHi: food.nameHi,
          aliases: food.aliases,
          kcal: food.kcal.toFixed(2),
          proteinG: food.proteinG.toFixed(2),
          fatG: food.fatG.toFixed(2),
          carbG: food.carbG.toFixed(2),
          fibreG: food.fibreG.toFixed(2),
          sodiumMg: food.sodiumMg.toFixed(2),
          addedSugarG: food.addedSugarG.toFixed(2),
          saturatedFatG: food.saturatedFatG.toFixed(2),
          tags: food.tags,
          suitableFor: food.suitableFor,
          allergens: food.allergens,
          costTier: food.costTier,
          source: food.source,
          sourceRef: food.sourceRef,
        });

        existing ? updated++ : imported++;

        // Measures are replaced wholesale: an edited row is the operator's new intent, and merging
        // would leave a deleted katori silently in place.
        await manager.delete(HouseholdMeasureEntity, {
          foodId: (saved as FoodEntity).id,
        });
        for (const m of food.measures) {
          await manager.save(HouseholdMeasureEntity, {
            foodId: (saved as FoodEntity).id,
            label: m.label,
            grams: m.grams.toFixed(2),
            isDefault: m.isDefault,
          });
        }
      }
    });

    return { imported, updated, skipped: 0, errors: [] };
  }

  /// Search across name, Hindi name AND aliases — the alias list is the point: people type
  /// "chapati", "maggi", "golgappa". Unverified foods are excluded; a half-entered row must never
  /// reach a user's plan.
  /// Adds the photograph to each result (D-83). The rest of the shape is unchanged — the app reads
  /// `kcal` and `measures` from these rows, so only new keys are added, never renamed ones.
  async searchWithImages(
    query: string,
    limit = 30,
    offset = 0,
    suitableFor?: string,
  ) {
    const rows = await this.search(query, limit, offset, suitableFor);
    return rows.map((food) => ({
      ...food,
      image_url:
        food.imageSlug === null || food.imageSlug === undefined
          ? null
          : `/food-images/${food.imageSlug}`,
      image_attribution: food.imageAttribution ?? null,
    }));
  }

  /// [offset] pages the result. The order is by name and is total, so a page boundary lands in
  /// the same place on every request — without a deterministic sort, paging silently repeats and
  /// skips rows as the planner changes its mind.
  /// [suitableFor] narrows to one food preference (docs/03 §2) — the app's category control.
  /// Filtered HERE and not in the client: the list is paged, so a client-side filter would only
  /// ever filter the pages it happens to hold and the counts would change as the user scrolled.
  async search(
    query: string,
    limit = 30,
    offset = 0,
    suitableFor?: string,
  ): Promise<FoodEntity[]> {
    const qb = this.foods
      .createQueryBuilder('food')
      .leftJoinAndSelect('food.measures', 'measure')
      .where('food.isVerified = true')
      .take(limit)
      .skip(offset)
      .orderBy('food.name', 'ASC')
      .addOrderBy('food.id', 'ASC');

    if (suitableFor) {
      qb.andWhere(':pref = ANY(food."suitableFor")', { pref: suitableFor });
    }

    if (query) {
      qb.andWhere(
        `(food.name ILIKE :q OR food."nameHi" ILIKE :q
          OR EXISTS (SELECT 1 FROM unnest(food.aliases) alias WHERE alias ILIKE :q))`,
        { q: `%${query}%` },
      );
    }

    return qb.getMany();
  }

  /// Marks foods live. Deliberately a separate act from importing: an operator reviews what they
  /// typed before it can reach a plan. Passing no ids verifies everything unverified, which is a
  /// development convenience, not a habit — review the rows first.
  async verify(ids?: string[]): Promise<{ verified: number }> {
    const result = ids?.length
      ? await this.foods.update(ids, { isVerified: true })
      : await this.foods.update({ isVerified: false }, { isVerified: true });

    return { verified: result.affected ?? 0 };
  }

  async count(): Promise<{ total: number; verified: number }> {
    const [total, verified] = await Promise.all([
      this.foods.count(),
      this.foods.countBy({ isVerified: true }),
    ]);
    return { total, verified };
  }
}
