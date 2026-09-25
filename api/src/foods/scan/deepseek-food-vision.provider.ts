import { Logger } from '@nestjs/common';
import type { FoodVisionProvider, ScanImageType } from './food-vision.provider';
import {
  ESTIMATE_JSON_EXAMPLE,
  ESTIMATE_PROMPT,
  NOT_FOOD,
  parseEstimate,
  type PlateEstimate,
} from './plate-estimate';

const ENDPOINT = 'https://api.deepseek.com/chat/completions';
const MODEL = 'deepseek-flash';

/// Below the app's 45 s upload timeout, so the server answers with a 503 it can explain rather than
/// the phone giving up on a request that is still running.
const TIMEOUT_MS = 40_000;

/// `deepseek-flash` reasons before it answers, and the reasoning counts against this. At 1,024 the
/// answer came back empty (`finish_reason: length`). The cap only stops a runaway reply.
const MAX_TOKENS = 8192;

type ChatCompletion = {
  choices?: { message?: { content?: string | null }; finish_reason?: string }[];
};

/// D-239/D-240. DeepSeek vision behind the same adapter as Claude (docs/04 §11). Plain `fetch`
/// against the documented Chat Completions endpoint — no SDK for one POST.
export class DeepSeekFoodVisionProvider implements FoodVisionProvider {
  private readonly logger = new Logger(DeepSeekFoodVisionProvider.name);

  constructor(private readonly apiKey: string) {}

  async estimate(
    image: Buffer,
    mediaType: ScanImageType,
  ): Promise<PlateEstimate> {
    const response = await fetch(ENDPOINT, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        Authorization: `Bearer ${this.apiKey}`,
      },
      body: JSON.stringify({
        model: MODEL,
        max_tokens: MAX_TOKENS,
        // JSON mode needs the word "json" in the prompt and an example of the shape (its docs).
        response_format: { type: 'json_object' },
        messages: [
          { role: 'system', content: ESTIMATE_PROMPT + ESTIMATE_JSON_EXAMPLE },
          {
            role: 'user',
            content: [
              { type: 'text', text: 'Estimate this meal.' },
              {
                type: 'image_url',
                image_url: {
                  url: `data:${mediaType};base64,${image.toString('base64')}`,
                },
              },
            ],
          },
        ],
      }),
      signal: AbortSignal.timeout(TIMEOUT_MS),
    });

    // The status only: the body can echo the request, and the request carried a meal photo.
    if (!response.ok) throw new Error(`deepseek answered ${response.status}`);

    const body = (await response.json()) as ChatCompletion;
    const choice = body.choices?.[0];
    // DeepSeek documents that JSON mode "may occasionally return empty content" — that, a
    // truncated answer, or anything off-schema is "not recognised", never a guess.
    const estimate = parseEstimate(choice?.message?.content);
    if (!estimate) {
      this.logger.warn(
        `scan answer failed the checks (finish: ${choice?.finish_reason ?? 'none'})`,
      );
      return NOT_FOOD;
    }
    return estimate;
  }
}
