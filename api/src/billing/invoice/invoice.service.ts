import { HttpStatus, Injectable, NotFoundException } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { InjectRepository } from '@nestjs/typeorm';
import { Repository } from 'typeorm';
import type { AllConfigType } from '../../config/config.type';
import type { PaymentOrderEntity } from '../entities/payment-order.entity';
import { InvoiceEntity } from './invoice.entity';
import { renderInvoicePdf } from './invoice-pdf';
import {
  GST_RATE_BPS,
  fiscalYear,
  invoiceNumber,
  splitInclusive,
  type InvoiceKind,
} from './invoice-rules';

const INVOICE_NOT_FOUND = 'That invoice does not exist.';

export type InvoiceView = {
  id: string;
  number: string;
  kind: InvoiceKind;
  issued_at: string;
  description: string;
  total_paise: string;
};

type Seller = {
  sellerGstin: string;
  sellerLegalName: string;
  sellerAddress: string;
  sellerStateCode: string;
  sacCode: string;
};

/**
 * GST tax invoices for Cashfree sales, and a credit note for each refund (D-255).
 *
 * Only once the business is GST-registered — with no GSTIN configured nothing is issued, because a
 * tax invoice from an unregistered seller is not one. Store sales (Play, App Store) are invoiced by
 * the store, not here.
 */
@Injectable()
export class InvoiceService {
  constructor(
    @InjectRepository(InvoiceEntity)
    private readonly invoices: Repository<InvoiceEntity>,
    private readonly config: ConfigService<AllConfigType>,
  ) {}

  get configured(): boolean {
    return this.seller() !== null;
  }

  /// After a verified payment. Idempotent: a retried webhook gets the invoice already issued.
  async issueFor(
    order: PaymentOrderEntity,
    now: Date,
  ): Promise<InvoiceEntity | null> {
    const seller = this.seller();
    if (!seller) return null;
    const existing = await this.invoices.findOne({
      where: { paymentOrderId: order.id, kind: 'invoice' },
    });
    if (existing) return existing;

    const split = splitInclusive(BigInt(order.amountPaise), GST_RATE_BPS, true);
    return this.write('invoice', order, seller, now, {
      refersToId: null,
      description: describe(order),
      taxablePaise: split.taxablePaise.toString(),
      cgstPaise: split.cgstPaise.toString(),
      sgstPaise: split.sgstPaise.toString(),
      igstPaise: split.igstPaise.toString(),
      totalPaise: split.totalPaise.toString(),
    });
  }

  /// After a refund: the whole invoice, credited back. Null when the sale had no invoice.
  async creditNoteFor(
    order: PaymentOrderEntity,
    now: Date,
  ): Promise<InvoiceEntity | null> {
    const seller = this.seller();
    const original = await this.invoices.findOne({
      where: { paymentOrderId: order.id, kind: 'invoice' },
    });
    if (!seller || !original) return null;
    const existing = await this.invoices.findOne({
      where: { paymentOrderId: order.id, kind: 'credit_note' },
    });
    if (existing) return existing;

    return this.write('credit_note', order, seller, now, {
      refersToId: original.id,
      description: original.description,
      taxablePaise: original.taxablePaise,
      cgstPaise: original.cgstPaise,
      sgstPaise: original.sgstPaise,
      igstPaise: original.igstPaise,
      totalPaise: original.totalPaise,
    });
  }

  async listFor(userId: number): Promise<InvoiceView[]> {
    const rows = await this.invoices.find({
      where: { userId },
      order: { issuedAt: 'DESC' },
    });
    return rows.map((i) => ({
      id: i.id,
      number: i.number,
      kind: i.kind,
      issued_at: i.issuedAt.toISOString(),
      description: i.description,
      total_paise: String(i.totalPaise),
    }));
  }

  /// The caller's own invoice only — someone else's id answers 404, not 403.
  async pdfFor(
    userId: number,
    id: string,
  ): Promise<{ number: string; pdf: Buffer }> {
    const invoice = await this.invoices.findOne({ where: { id, userId } });
    if (!invoice) {
      throw new NotFoundException({
        status: HttpStatus.NOT_FOUND,
        error: { code: 'INVOICE_NOT_FOUND', user_message: INVOICE_NOT_FOUND },
      });
    }
    const original = invoice.refersToId
      ? await this.invoices.findOne({ where: { id: invoice.refersToId } })
      : null;
    return {
      number: invoice.number,
      pdf: await renderInvoicePdf(invoice, original),
    };
  }

  /// Takes the next number and writes the row in one transaction, so a failed insert gives the
  /// number back and the series stays consecutive.
  private write(
    kind: InvoiceKind,
    order: PaymentOrderEntity,
    seller: Seller,
    now: Date,
    lines: Pick<
      InvoiceEntity,
      | 'refersToId'
      | 'description'
      | 'taxablePaise'
      | 'cgstPaise'
      | 'sgstPaise'
      | 'igstPaise'
      | 'totalPaise'
    >,
  ): Promise<InvoiceEntity> {
    const fy = fiscalYear(now);
    return this.invoices.manager.transaction(async (m) => {
      const [{ seq }] = (await m.query(
        `INSERT INTO "invoice_sequence" ("fiscalYear", "kind", "next") VALUES ($1, $2, 2)
         ON CONFLICT ("fiscalYear", "kind")
         DO UPDATE SET "next" = "invoice_sequence"."next" + 1
         RETURNING "next" - 1 AS seq`,
        [fy, kind],
      )) as { seq: number }[];
      return m.getRepository(InvoiceEntity).save({
        number: invoiceNumber(kind, fy, Number(seq)),
        kind,
        fiscalYear: fy,
        userId: order.userId,
        paymentOrderId: order.id,
        issuedAt: now,
        ...seller,
        // B2C with no address on record: supplied where the seller is.
        placeOfSupply: seller.sellerStateCode,
        rateBps: GST_RATE_BPS,
        ...lines,
      });
    });
  }

  private seller(): Seller | null {
    const get = <K extends keyof AllConfigType['invoice']>(k: K) =>
      this.config.get(`invoice.${k}`, { infer: true });
    const s = {
      sellerGstin: get('sellerGstin'),
      sellerLegalName: get('sellerLegalName'),
      sellerAddress: get('sellerAddress'),
      sellerStateCode: get('sellerStateCode'),
      sacCode: get('sacCode'),
    };
    return Object.values(s).every(Boolean) ? (s as Seller) : null;
  }
}

/// `Eatzify Pro plan, 3 months`.
function describe(order: PaymentOrderEntity): string {
  const tier = order.tier.charAt(0) + order.tier.slice(1).toLowerCase();
  const months = parseInt(order.duration, 10);
  return `Eatzify ${tier} plan, ${months} ${months === 1 ? 'month' : 'months'}`;
}
