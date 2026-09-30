import { randomBytes } from 'crypto';
import { decryptField, encryptField } from '../src/utils/field-crypto';
import {
  fiscalYear,
  inr,
  invoiceNumber,
  splitInclusive,
} from '../src/billing/invoice/invoice-rules';
import { InvoiceService } from '../src/billing/invoice/invoice.service';
import { renderInvoicePdf } from '../src/billing/invoice/invoice-pdf';
import { KycService } from '../src/partner/kyc.service';

/// D-255: GST invoices for Cashfree sales, and partner KYC asked for only once a payout is due.

const NOW = new Date('2026-09-30T10:00:00Z');
const KEY = randomBytes(32).toString('base64');

describe('sealed fields', () => {
  it('should round-trip and never store the clear text', () => {
    const sealed = encryptField('ABCDE1234F', KEY);
    expect(sealed).not.toContain('ABCDE1234F');
    expect(decryptField(sealed, KEY)).toBe('ABCDE1234F');
  });

  it('should refuse to open with the wrong key or a tampered value', () => {
    const sealed = encryptField('123456789012', KEY);
    expect(() =>
      decryptField(sealed, randomBytes(32).toString('base64')),
    ).toThrow();
    const parts = sealed.split('.');
    parts[3] = Buffer.from('tampered').toString('base64');
    expect(() => decryptField(parts.join('.'), KEY)).toThrow();
  });
});

describe('invoice rules', () => {
  it.each([
    ['2026-03-31T18:29:00Z', '2025-26'], // 23:59 IST on 31 Mar
    ['2026-03-31T18:30:00Z', '2026-27'], // 00:00 IST on 1 Apr
    ['2027-01-15T00:00:00Z', '2026-27'],
  ])('should put %s in financial year %s', (at, fy) => {
    expect(fiscalYear(new Date(at))).toBe(fy);
  });

  it('should number invoices and credit notes apart, within 16 characters', () => {
    expect(invoiceNumber('invoice', '2026-27', 1)).toBe('EZ2627-000001');
    expect(invoiceNumber('credit_note', '2026-27', 42)).toBe('CN2627-000042');
    expect(
      invoiceNumber('invoice', '2026-27', 999_999).length,
    ).toBeLessThanOrEqual(16);
  });

  it('should split an inclusive price so the parts add back exactly', () => {
    for (const total of [49_900n, 99_900n, 1n, 123_457n]) {
      const s = splitInclusive(total, 1800, true);
      expect(s.taxablePaise + s.cgstPaise + s.sgstPaise + s.igstPaise).toBe(
        total,
      );
      expect(s.igstPaise).toBe(0n);
    }
    // ₹499 incl. 18 %: ₹422.88 taxable, ₹76.12 tax.
    expect(splitInclusive(49_900n, 1800, true)).toMatchObject({
      taxablePaise: 42_288n,
      cgstPaise: 3_806n,
      sgstPaise: 3_806n,
    });
    expect(splitInclusive(49_900n, 1800, false)).toMatchObject({
      igstPaise: 7_612n,
    });
  });

  it('should format paise with Indian grouping and no float', () => {
    expect(inr(123_456_750n)).toBe('INR 12,34,567.50');
    expect(inr('-5050')).toBe('-INR 50.50');
  });
});

const SELLER = {
  sellerGstin: '07ABCDE1234F1Z5',
  sellerLegalName: 'Zynthovo Private Limited',
  sellerAddress: 'New Delhi',
  sellerStateCode: '07',
  sacCode: '998439',
};

function invoiceSetup(seller: Record<string, string | null> = SELLER) {
  const rows: Record<string, unknown>[] = [];
  let seq = 0;
  const repo = {
    rows,
    findOne: ({ where }: { where: Record<string, unknown> }) =>
      Promise.resolve(
        rows.find((r) => Object.entries(where).every(([k, v]) => r[k] === v)) ??
          null,
      ),
    find: ({ where }: { where: Record<string, unknown> }) =>
      Promise.resolve(rows.filter((r) => r.userId === where.userId)),
    manager: {
      transaction: <T>(fn: (m: unknown) => Promise<T>) =>
        fn({
          query: () => Promise.resolve([{ seq: ++seq }]),
          getRepository: () => ({
            save: (r: Record<string, unknown>) => {
              const saved = { ...r, id: `i${rows.length + 1}` };
              rows.push(saved);
              return Promise.resolve(saved);
            },
          }),
        }),
    },
  };
  const map: Record<string, string | null> = {
    'invoice.sellerGstin': seller.sellerGstin,
    'invoice.sellerLegalName': seller.sellerLegalName,
    'invoice.sellerAddress': seller.sellerAddress,
    'invoice.sellerStateCode': seller.sellerStateCode,
    'invoice.sacCode': seller.sacCode,
  };
  const config = { get: (k: string) => map[k] ?? null };
  return { service: new InvoiceService(repo as never, config as never), rows };
}

const ORDER = {
  id: 'o1',
  userId: 5,
  tier: 'PRO',
  duration: '3M',
  amountPaise: '99900',
} as never;

describe('invoices', () => {
  it('should issue nothing while the business is not GST-registered', async () => {
    const { service, rows } = invoiceSetup({ ...SELLER, sellerGstin: null });
    expect(await service.issueFor(ORDER, NOW)).toBeNull();
    expect(rows).toHaveLength(0);
  });

  it('should issue one numbered invoice per paid order, even when the webhook repeats', async () => {
    const { service, rows } = invoiceSetup();
    await service.issueFor(ORDER, NOW);
    await service.issueFor(ORDER, NOW);

    expect(rows).toHaveLength(1);
    expect(rows[0]).toMatchObject({
      number: 'EZ2627-000001',
      kind: 'invoice',
      description: 'Eatzify Pro plan, 3 months',
      placeOfSupply: '07',
      totalPaise: '99900',
      taxablePaise: '84661',
    });
  });

  it('should credit the whole invoice back on a refund', async () => {
    const { service, rows } = invoiceSetup();
    await service.issueFor(ORDER, NOW);
    await service.creditNoteFor(ORDER, NOW);

    expect(rows[1]).toMatchObject({
      kind: 'credit_note',
      refersToId: rows[0].id,
      totalPaise: '99900',
      number: expect.stringMatching(/^CN2627-\d{6}$/) as unknown,
    });
  });

  it('should render a PDF of an invoice', async () => {
    const { service, rows } = invoiceSetup();
    await service.issueFor(ORDER, NOW);
    const { pdf, number } = await service.pdfFor(5, rows[0].id as string);
    expect(number).toBe('EZ2627-000001');
    expect(pdf.subarray(0, 4).toString()).toBe('%PDF');
  });

  it('should not hand one account another account’s invoice', async () => {
    const { service, rows } = invoiceSetup();
    await service.issueFor(ORDER, NOW);
    await expect(service.pdfFor(6, rows[0].id as string)).rejects.toMatchObject(
      {
        status: 404,
      },
    );
  });

  it('should render a credit note that names its invoice', async () => {
    const { rows, service } = invoiceSetup();
    await service.issueFor(ORDER, NOW);
    await service.creditNoteFor(ORDER, NOW);
    const pdf = await renderInvoicePdf(rows[1] as never, rows[0] as never);
    expect(pdf.length).toBeGreaterThan(500);
  });
});

function kycSetup(
  duePaise: bigint,
  existing: Record<string, unknown> | null = null,
) {
  let row = existing;
  const repo = {
    findOne: () => Promise.resolve(row),
    save: (r: Record<string, unknown>) => {
      row = r;
      return Promise.resolve(r);
    },
  };
  const payouts = { settleableBalance: () => Promise.resolve(duePaise) };
  const config = { get: () => KEY };
  return {
    service: new KycService(repo as never, payouts as never, config as never),
    row: () => row,
  };
}

const SUBMISSION = {
  holderName: 'Test Partner',
  pan: 'ABCDE1234F',
  accountNumber: '123456789012',
  ifsc: 'HDFC0001234',
  gstin: null,
};

describe('partner KYC', () => {
  it('should not ask for KYC while nothing is due', async () => {
    const { service } = kycSetup(99_999n);
    expect(await service.viewFor(7, NOW)).toMatchObject({
      required: false,
      status: 'none',
    });
  });

  it('should ask for KYC once a payout is due', async () => {
    const { service } = kycSetup(100_000n);
    expect(await service.viewFor(7, NOW)).toMatchObject({
      required: true,
      due_paise: '100000',
    });
  });

  it('should seal the full numbers and keep only the last four readable', async () => {
    const { service, row } = kycSetup(100_000n);
    const view = await service.submit(7, SUBMISSION, NOW);

    expect(view).toMatchObject({
      required: false,
      status: 'pending',
      pan_last4: '234F',
      bank_last4: '9012',
    });
    expect(JSON.stringify(row())).not.toContain('ABCDE1234F');
    expect(JSON.stringify(row())).not.toContain('123456789012');
    expect(await service.reveal(7)).toMatchObject({
      pan: 'ABCDE1234F',
      account_number: '123456789012',
    });
  });

  it('should ask again after a rejection, and restart the bank freeze on a new account', async () => {
    const { service, row } = kycSetup(100_000n);
    await service.submit(7, SUBMISSION, new Date('2026-09-01T00:00:00Z'));
    await service.review(7, 'rejected', NOW);
    expect(await service.viewFor(7, NOW)).toMatchObject({
      required: true,
      status: 'rejected',
    });

    await service.submit(
      7,
      { ...SUBMISSION, accountNumber: '999988887777' },
      NOW,
    );
    expect(row()).toMatchObject({ bankChangedAt: NOW, status: 'pending' });
  });

  it('should keep the bank freeze date when only the name changes', async () => {
    const first = new Date('2026-09-01T00:00:00Z');
    const { service, row } = kycSetup(100_000n);
    await service.submit(7, SUBMISSION, first);
    await service.submit(7, { ...SUBMISSION, holderName: 'Test P' }, NOW);
    expect(row()).toMatchObject({ bankChangedAt: first });
  });
});
