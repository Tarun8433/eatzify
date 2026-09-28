import { FoodsController } from '../src/foods/foods.controller';

/// D-238. The app's category chips send `group=` (one or several docs/03 §4 groups). An unknown
/// group is rejected, never ignored: ignoring it would answer "vegetables" with the whole table.

const controllerRecording = (calls: unknown[][]) =>
  new FoodsController({
    searchWithImages: (...args: unknown[]) => {
      calls.push(args);
      return Promise.resolve([]);
    },
  } as never);

describe('GET /foods?group=', () => {
  it('should pass every named group to the search', async () => {
    const calls: unknown[][] = [];

    await controllerRecording(calls).search(
      '',
      undefined,
      undefined,
      undefined,
      'pulse,meat,fish,egg',
    );

    expect(calls[0][4]).toEqual(['pulse', 'meat', 'fish', 'egg']);
  });

  it('should reject a group the vocabulary does not know', () => {
    expect(() =>
      controllerRecording([]).search(
        '',
        undefined,
        undefined,
        undefined,
        'veg,rocks',
      ),
    ).toThrow(expect.objectContaining({ status: 400 }));
  });

  it('should search everything when no group is named', async () => {
    const calls: unknown[][] = [];

    await controllerRecording(calls).search('dal');

    expect(calls[0][4]).toBeUndefined();
  });
});
