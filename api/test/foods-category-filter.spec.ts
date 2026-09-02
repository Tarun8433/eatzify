import { BadRequestException } from '@nestjs/common';
import { FoodsController } from '../src/foods/foods.controller';
import type { FoodsService } from '../src/foods/foods.service';

/// The food tab's category control (docs/03 §2 food preference). The filter runs HERE and not in
/// the app: the list is paged, so a client-side filter would only ever filter the pages already
/// fetched, and the list would change as the user scrolled.

type SearchArgs = [string, number, number, string | undefined];

const controllerWith = () => {
  const calls: SearchArgs[] = [];
  const service = {
    searchWithImages: (...args: SearchArgs) => {
      calls.push(args);
      return Promise.resolve([]);
    },
  } as unknown as FoodsService;

  return { controller: new FoodsController(service), calls };
};

describe('GET /foods category filter', () => {
  it('should pass a known preference through to the query', async () => {
    const { controller, calls } = controllerWith();

    await controller.search('', undefined, undefined, 'veg');

    expect(calls[0]).toEqual(['', 20, 0, 'veg']);
  });

  it('should leave the filter off when no preference is asked for', async () => {
    const { controller, calls } = controllerWith();

    await controller.search('dal');

    expect(calls[0]).toEqual(['dal', 20, 0, undefined]);
  });

  /// Rejected, not ignored. Returning the whole table to someone who asked for vegetarian food is
  /// the one failure mode this filter must not have.
  it('should reject a preference the vocabulary does not know', () => {
    const { controller, calls } = controllerWith();

    expect(() =>
      controller.search('', undefined, undefined, 'pescatarian'),
    ).toThrow(BadRequestException);
    // And the database is never asked.
    expect(calls).toEqual([]);
  });
});
