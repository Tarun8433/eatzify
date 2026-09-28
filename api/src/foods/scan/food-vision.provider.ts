import Anthropic from '@anthropic-ai/sdk';
import { Logger } from '@nestjs/common';
import {
  ANSWER_JSON_SCHEMA,
  ESTIMATE_PROMPT,
  NOT_FOOD,
  parseEstimate,
  type PlateEstimate,
} from './plate-estimate';

export type ScanImageType = 'image/jpeg' | 'image/png';

/// docs/04 §11: the vendor is swappable, and its response shape stops at this interface.
export interface FoodVisionProvider {
  /// What the photographed plate holds, item by item, with nutrition for each item's weight
  /// (D-240). A photo that is not food — or an answer that fails the checks — is `NOT_FOOD`.
  estimate(image: Buffer, mediaType: ScanImageType): Promise<PlateEstimate>;
}

export const FOOD_VISION_PROVIDER = Symbol('FOOD_VISION_PROVIDER');

/// D-238/D-240. Claude vision behind the adapter.
export class AnthropicFoodVisionProvider implements FoodVisionProvider {
  private readonly logger = new Logger(AnthropicFoodVisionProvider.name);
  private readonly client: Anthropic;

  constructor(apiKey: string) {
    this.client = new Anthropic({ apiKey });
  }

  async estimate(
    image: Buffer,
    mediaType: ScanImageType,
  ): Promise<PlateEstimate> {
    const response = await this.client.beta.messages.create({
      model: 'claude-opus-5',
      // Thinking counts against this; the answer itself is a few hundred tokens.
      max_tokens: 8192,
      thinking: { type: 'adaptive' },
      output_config: {
        effort: 'low',
        format: { type: 'json_schema', schema: ANSWER_JSON_SCHEMA },
      },
      // A declined request is re-run on Anthropic's recommended fallback model server-side.
      betas: ['server-side-fallback-2026-07-01'],
      fallbacks: 'default',
      system: ESTIMATE_PROMPT,
      messages: [
        {
          role: 'user',
          content: [
            {
              type: 'image',
              source: {
                type: 'base64',
                media_type: mediaType,
                data: image.toString('base64'),
              },
            },
            { type: 'text', text: 'Estimate this meal.' },
          ],
        },
      ],
    });

    // Checked before content: a refusal (even after the fallback) has nothing to read.
    if (response.stop_reason === 'refusal') {
      this.logger.warn(
        `scan declined: ${response.stop_details?.category ?? 'uncategorised'}`,
      );
      return NOT_FOOD;
    }

    const text = response.content.find((b) => b.type === 'text')?.text;
    const estimate = parseEstimate(text);
    if (!estimate) {
      this.logger.warn(
        `scan answer failed the checks (stop: ${response.stop_reason})`,
      );
      return NOT_FOOD;
    }
    return estimate;
  }
}
