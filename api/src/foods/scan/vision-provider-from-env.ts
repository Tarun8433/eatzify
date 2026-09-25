import {
  AnthropicFoodVisionProvider,
  type FoodVisionProvider,
} from './food-vision.provider';
import { DeepSeekFoodVisionProvider } from './deepseek-food-vision.provider';

/// `FOOD_VISION_PROVIDER` picks the vendor (D-239); a provider without its key is off, the same as
/// `none` — scanning answers 503 SCAN_UNAVAILABLE rather than the API failing to boot.
export function visionProviderFromEnv(
  env: NodeJS.ProcessEnv = process.env,
): FoodVisionProvider | null {
  switch (env.FOOD_VISION_PROVIDER) {
    case 'deepseek':
      return env.DEEPSEEK_API_KEY
        ? new DeepSeekFoodVisionProvider(env.DEEPSEEK_API_KEY)
        : null;
    case 'anthropic':
      return env.ANTHROPIC_API_KEY
        ? new AnthropicFoodVisionProvider(env.ANTHROPIC_API_KEY)
        : null;
    default:
      return null;
  }
}
