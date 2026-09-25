import { DeepSeekFoodVisionProvider } from '../src/foods/scan/deepseek-food-vision.provider';
import { AnthropicFoodVisionProvider } from '../src/foods/scan/food-vision.provider';
import { visionProviderFromEnv } from '../src/foods/scan/vision-provider-from-env';

/// D-239/D-240. DeepSeek behind the same adapter as Claude: the request is the documented Chat
/// Completions shape, and whatever comes back must pass the estimate checks — an empty, broken or
/// failed reply is "not recognised", never a guess.

const photo = Buffer.from('jpeg-bytes');

const plate = JSON.stringify({
  is_food: true,
  dish_name: 'Rice with dal tadka',
  confidence: 0.8,
  items: [
    {
      name: 'Rice (cooked white)',
      grams: 200,
      kcal: 252,
      protein_g: 5.4,
      carb_g: 56,
      fat_g: 0.6,
      fibre_g: 0.8,
      sodium_mg: 2,
      added_sugar_g: 0,
      saturated_fat_g: 0.2,
    },
  ],
});

const replyWith = (content: string | null, status = 200) =>
  jest.spyOn(global, 'fetch').mockResolvedValue(
    new Response(
      JSON.stringify({
        choices: [{ message: { content }, finish_reason: 'stop' }],
      }),
      { status },
    ),
  );

const estimate = () =>
  new DeepSeekFoodVisionProvider('sk-test').estimate(photo, 'image/jpeg');

describe('DeepSeekFoodVisionProvider', () => {
  afterEach(() => jest.restoreAllMocks());

  it('should send the photo as a data URL and ask for JSON', async () => {
    const fetchMock = replyWith(plate);

    await estimate();

    const [url, init] = fetchMock.mock.calls[0];
    const body = JSON.parse(String(init?.body));
    expect(url).toBe('https://api.deepseek.com/chat/completions');
    expect((init?.headers as Record<string, string>).Authorization).toBe(
      'Bearer sk-test',
    );
    expect(body.model).toBe('deepseek-flash');
    expect(body.response_format).toEqual({ type: 'json_object' });
    // Its JSON mode needs the word "json" in the prompt.
    expect(body.messages[0].content).toContain('json');
    expect(body.messages[1].content[1].image_url.url).toBe(
      `data:image/jpeg;base64,${photo.toString('base64')}`,
    );
  });

  it('should read a valid estimate', async () => {
    replyWith(plate);

    const result = await estimate();

    expect(result.isFood).toBe(true);
    expect(result.dishName).toBe('Rice with dal tadka');
    expect(result.items[0]).toMatchObject({
      name: 'Rice (cooked white)',
      kcal: 252,
    });
  });

  it('should treat the empty content DeepSeek documents as not recognised', async () => {
    replyWith(null);

    expect((await estimate()).isFood).toBe(false);
  });

  it('should fail loudly on an error status, so the scan is not counted', async () => {
    replyWith('{"error": "rate limited"}', 429);

    await expect(estimate()).rejects.toThrow('deepseek answered 429');
  });
});

describe('visionProviderFromEnv', () => {
  it('should pick the vendor the config names, when its key is present', () => {
    expect(
      visionProviderFromEnv({
        FOOD_VISION_PROVIDER: 'deepseek',
        DEEPSEEK_API_KEY: 'k',
      }),
    ).toBeInstanceOf(DeepSeekFoodVisionProvider);
    expect(
      visionProviderFromEnv({
        FOOD_VISION_PROVIDER: 'anthropic',
        ANTHROPIC_API_KEY: 'k',
      }),
    ).toBeInstanceOf(AnthropicFoodVisionProvider);
  });

  it('should leave scanning off without a provider or without its key', () => {
    expect(
      visionProviderFromEnv({ FOOD_VISION_PROVIDER: 'deepseek' }),
    ).toBeNull();
    expect(visionProviderFromEnv({ ANTHROPIC_API_KEY: 'k' })).toBeNull();
    expect(visionProviderFromEnv({ FOOD_VISION_PROVIDER: 'none' })).toBeNull();
  });
});
