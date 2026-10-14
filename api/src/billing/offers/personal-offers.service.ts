import {
  ConflictException,
  HttpStatus,
  Injectable,
  Logger,
  NotFoundException,
  ServiceUnavailableException,
  UnprocessableEntityException,
} from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { InjectRepository } from '@nestjs/typeorm';
import { Repository } from 'typeorm';
import type { AllConfigType } from '../../config/config.type';
import { UserEntity } from '../../users/infrastructure/persistence/relational/entities/user.entity';
import {
  OFFER_CATALOG_UNAVAILABLE,
  OFFER_NOT_CASHFREE,
  OFFER_NOT_FOUND,
} from '../billing-copy';
import { CheckoutService, type CheckoutView } from '../checkout.service';
import { PersonalOfferEntity } from '../entities/personal-offer.entity';
import { PriceService } from '../price.service';
import { PlayClient } from '../store/play.client';
import {
  OFFER_ERRORS,
  expiryFrom,
  newOfferCode,
  offerLink,
  offerRequestError,
  offerStatus,
  playCatalogue,
  playPurchaseRedeems,
  redeemableBy,
  type OfferRequest,
  type OfferStatus,
  type PlayCatalogueOffer,
  type PlayLine,
} from './personal-offer-rules';

/// What the dashboard sees. `link` is what the admin sends; `note` never leaves the dashboard.
export type AdminOfferView = {
  id: string;
  code: string;
  link: string;
  user_id: number;
  channel: string;
  tier: string;
  duration: string;
  amount_paise: number | null;
  play_product_id: string | null;
  play_base_plan_id: string | null;
  play_offer_id: string | null;
  note: string | null;
  status: OfferStatus;
  expires_at: string;
  used_at: string | null;
  revoked_at: string | null;
  created_by_user_id: number;
  created_at: string;
};

/// What the app sees (`GET /billing/offers/:code`). Every price is the server's or Play's.
export type AppOfferView = {
  code: string;
  channel: string;
  tier: string;
  duration: string;
  expires_at: string;
  price_paise: number | null;
  regular_price_paise: number | null;
  play: { product_id: string; base_plan_id: string; offer_id: string } | null;
};

const CATALOG_TTL_MS = 10 * 60_000;

/// D-265: personal offers — made by an admin for one person, opened by them from a link.
@Injectable()
export class PersonalOffersService {
  private readonly log = new Logger(PersonalOffersService.name);
  // ponytail: per-process cache, same as PlayClient.liveBasePlans; one API container today.
  private catalog: { at: number; offers: PlayCatalogueOffer[] } | null = null;

  constructor(
    @InjectRepository(PersonalOfferEntity)
    private readonly offers: Repository<PersonalOfferEntity>,
    @InjectRepository(UserEntity)
    private readonly users: Repository<UserEntity>,
    private readonly prices: PriceService,
    private readonly play: PlayClient,
    private readonly checkout_: CheckoutService,
    private readonly config: ConfigService<AllConfigType>,
  ) {}

  /// The live Play catalogue. Empty when Play is not configured; an error when Play is and fails,
  /// so an admin is not told "there are no offers" when there may be.
  async playCatalog(now = Date.now()): Promise<PlayCatalogueOffer[]> {
    if (!this.play.configured) return [];
    if (this.catalog && now - this.catalog.at < CATALOG_TTL_MS) {
      return this.catalog.offers;
    }
    try {
      const raw = await this.play.subscriptionCatalog();
      const offers = playCatalogue(raw.subscriptions, raw.offers);
      this.catalog = { at: now, offers };
      return offers;
    } catch (e) {
      this.log.warn(
        `could not read the Play catalogue: ${e instanceof Error ? e.message : 'unknown'}`,
      );
      throw new ServiceUnavailableException({
        status: HttpStatus.SERVICE_UNAVAILABLE,
        error: {
          code: 'PLAY_CATALOG_UNAVAILABLE',
          user_message: OFFER_CATALOG_UNAVAILABLE,
        },
      });
    }
  }

  async create(
    input: OfferRequest & { userId: number; note?: string | null },
    createdByUserId: number,
    now: Date,
  ): Promise<AdminOfferView> {
    const listPaise = await this.prices.priceOf(input.tier, input.duration);
    const error = offerRequestError(input, listPaise);
    if (error) throw invalid(error);

    if (input.channel === 'play') {
      const match = (await this.playCatalog()).find(
        (o) =>
          o.product_id === input.playProductId &&
          o.base_plan_id === input.playBasePlanId &&
          o.offer_id === input.playOfferId &&
          o.tier === input.tier &&
          o.duration === input.duration,
      );
      if (!match) throw invalid(OFFER_ERRORS.notInCatalogue);
    }

    if ((await this.users.count({ where: { id: input.userId } })) === 0) {
      throw new NotFoundException({
        status: HttpStatus.NOT_FOUND,
        error: { code: 'USER_NOT_FOUND', user_message: 'No such user.' },
      });
    }

    const isPlay = input.channel === 'play';
    // ponytail: 128 random bits; a collision is left to the UNIQUE constraint to refuse.
    const row = await this.offers.save(
      this.offers.create({
        code: newOfferCode(),
        userId: input.userId,
        tier: input.tier,
        duration: input.duration,
        channel: input.channel,
        playProductId: isPlay ? input.playProductId! : null,
        playBasePlanId: isPlay ? input.playBasePlanId! : null,
        playOfferId: isPlay ? input.playOfferId! : null,
        amountPaise: isPlay ? null : String(input.amountPaise),
        note: input.note?.trim() || null,
        expiresAt: expiryFrom(now, input.expiresInDays),
        usedAt: null,
        revokedAt: null,
        createdByUserId,
      }),
    );
    return this.adminView(row, now);
  }

  async listFor(userId: number, now: Date): Promise<AdminOfferView[]> {
    const rows = await this.offers.find({
      where: { userId },
      order: { createdAt: 'DESC' },
    });
    return rows.map((r) => this.adminView(r, now));
  }

  /// Idempotent: revoking a revoked offer answers with it unchanged.
  async revoke(id: string, now: Date): Promise<AdminOfferView> {
    const row = await this.offers.findOne({ where: { id } });
    if (!row) {
      throw new NotFoundException({
        status: HttpStatus.NOT_FOUND,
        error: { code: 'OFFER_NOT_FOUND', user_message: 'No such offer.' },
      });
    }
    if (!row.revokedAt) {
      row.revokedAt = now;
      await this.offers.save(row);
    }
    return this.adminView(row, now);
  }

  async forCaller(
    userId: number,
    code: string,
    now: Date,
  ): Promise<AppOfferView> {
    const offer = await this.redeemable(userId, code, now);
    const regular = await this.prices.priceOf(offer.tier, offer.duration);
    return {
      code: offer.code,
      channel: offer.channel,
      tier: offer.tier,
      duration: offer.duration,
      expires_at: offer.expiresAt.toISOString(),
      price_paise:
        offer.channel === 'cashfree'
          ? Number(offer.amountPaise)
          : await this.playPriceOf(offer),
      regular_price_paise: regular ?? null,
      play:
        offer.channel === 'play'
          ? {
              product_id: offer.playProductId!,
              base_plan_id: offer.playBasePlanId!,
              offer_id: offer.playOfferId!,
            }
          : null,
    };
  }

  /// The caller has passed the `cashfreeOffered` gate already (the controller holds it). The amount
  /// is the stored one, capped at today's list price in case the plan was repriced since.
  async startCheckout(
    userId: number,
    code: string,
    idempotencyKey: string | null,
    now: Date,
  ): Promise<CheckoutView> {
    const offer = await this.redeemable(userId, code, now);
    if (offer.channel !== 'cashfree') {
      throw new ConflictException({
        status: HttpStatus.CONFLICT,
        error: { code: 'OFFER_NOT_CASHFREE', user_message: OFFER_NOT_CASHFREE },
      });
    }
    const list = await this.prices.priceOf(offer.tier, offer.duration);
    const stored = BigInt(offer.amountPaise!);
    const amountPaise =
      list !== undefined && BigInt(list) < stored ? BigInt(list) : stored;
    return this.checkout_.checkout({
      userId,
      tier: offer.tier,
      duration: offer.duration,
      idempotencyKey,
      now,
      personalOffer: { id: offer.id, amountPaise },
    });
  }

  /// After a successful Play verify. Never throws: the purchase is real and already granted, and
  /// a failure to mark the link spent must not turn it into an error on the phone.
  async markUsedByPlay(
    userId: number,
    code: string,
    line: PlayLine,
    now: Date,
  ): Promise<boolean> {
    try {
      const offer = await this.offers.findOne({ where: { code } });
      if (!playPurchaseRedeems(offer, userId, line, now)) return false;
      await this.offers.update({ id: offer!.id }, { usedAt: now });
      return true;
    } catch (e) {
      this.log.error(
        `personal offer not marked used for user ${userId}: ${e instanceof Error ? e.message : 'unknown'}`,
      );
      return false;
    }
  }

  private async redeemable(
    userId: number,
    code: string,
    now: Date,
  ): Promise<PersonalOfferEntity> {
    const offer = await this.offers.findOne({ where: { code } });
    if (!redeemableBy(offer, userId, now)) throw notFound();
    return offer!;
  }

  /// Play's price for the offer if the catalogue can say it; null (not an error) otherwise — the
  /// app shows Play's own price string from the store anyway.
  private async playPriceOf(
    offer: PersonalOfferEntity,
  ): Promise<number | null> {
    try {
      const match = (await this.playCatalog()).find(
        (o) =>
          o.product_id === offer.playProductId &&
          o.base_plan_id === offer.playBasePlanId &&
          o.offer_id === offer.playOfferId,
      );
      return match?.price_paise ?? null;
    } catch {
      // Already logged by playCatalog; the price is optional here by contract.
      return null;
    }
  }

  private adminView(row: PersonalOfferEntity, now: Date): AdminOfferView {
    const domain = this.config.getOrThrow('app.backendDomain', {
      infer: true,
    });
    return {
      id: row.id,
      code: row.code,
      link: offerLink(domain, row.code),
      user_id: row.userId,
      channel: row.channel,
      tier: row.tier,
      duration: row.duration,
      amount_paise: row.amountPaise === null ? null : Number(row.amountPaise),
      play_product_id: row.playProductId,
      play_base_plan_id: row.playBasePlanId,
      play_offer_id: row.playOfferId,
      note: row.note,
      status: offerStatus(row, now),
      expires_at: row.expiresAt.toISOString(),
      used_at: row.usedAt?.toISOString() ?? null,
      revoked_at: row.revokedAt?.toISOString() ?? null,
      created_by_user_id: row.createdByUserId,
      created_at: (row.createdAt ?? now).toISOString(),
    };
  }
}

function notFound(): NotFoundException {
  return new NotFoundException({
    status: HttpStatus.NOT_FOUND,
    error: { code: 'OFFER_NOT_FOUND', user_message: OFFER_NOT_FOUND },
  });
}

function invalid(userMessage: string): UnprocessableEntityException {
  return new UnprocessableEntityException({
    status: HttpStatus.UNPROCESSABLE_ENTITY,
    error: { code: 'OFFER_INVALID', user_message: userMessage },
  });
}
