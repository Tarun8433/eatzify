/// GST tax invoice arithmetic and numbering (D-255). Pure, so every edge is table-tested.

/// 18 % GST on the subscription, in basis points (docs/11 §2: every price is GST-inclusive).
export const GST_RATE_BPS = 1800;

const BPS = 10_000n;
/// IST is UTC+05:30; the Indian financial year turns at midnight IST on 1 April.
const IST_OFFSET_MS = (5 * 60 + 30) * 60 * 1000;

export type InvoiceKind = 'invoice' | 'credit_note';

/// `2026-27` for any moment from 1 Apr 2026 00:00 IST to 31 Mar 2027 23:59 IST.
export function fiscalYear(at: Date): string {
  const ist = new Date(at.getTime() + IST_OFFSET_MS);
  const year =
    ist.getUTCMonth() >= 3 ? ist.getUTCFullYear() : ist.getUTCFullYear() - 1;
  return `${year}-${String((year + 1) % 100).padStart(2, '0')}`;
}

/// `EZ2627-000001` / `CN2627-000001`: unique, consecutive per year and kind, 13 characters
/// (GST rule 46 caps it at 16).
export function invoiceNumber(
  kind: InvoiceKind,
  fy: string,
  seq: number,
): string {
  const prefix = kind === 'invoice' ? 'EZ' : 'CN';
  return `${prefix}${fy.slice(2, 4)}${fy.slice(5, 7)}-${String(seq).padStart(6, '0')}`;
}

export type TaxSplit = {
  taxablePaise: bigint;
  cgstPaise: bigint;
  sgstPaise: bigint;
  igstPaise: bigint;
  totalPaise: bigint;
};

/**
 * Splits a GST-inclusive price. Taxable value is rounded to the nearest paisa and the tax is the
 * remainder, so the parts always add back to exactly what the customer paid.
 *
 * Within the seller's state the tax is half CGST, half SGST; across states it is IGST. A B2C
 * sale with no address on record is supplied where the seller is, so it is intra-state.
 */
export function splitInclusive(
  totalPaise: bigint,
  rateBps: number,
  intraState: boolean,
): TaxSplit {
  const divisor = BPS + BigInt(rateBps);
  const taxablePaise = (totalPaise * BPS + divisor / 2n) / divisor;
  const tax = totalPaise - taxablePaise;
  const cgstPaise = intraState ? tax / 2n : 0n;
  const sgstPaise = intraState ? tax - cgstPaise : 0n;
  return {
    taxablePaise,
    cgstPaise,
    sgstPaise,
    igstPaise: intraState ? 0n : tax,
    totalPaise,
  };
}

/// `INR 12,34,567.50` from paise (Indian grouping), without a float anywhere (api rule 3). "INR"
/// rather than the rupee sign: the PDF's built-in font has no glyph for it.
export function inr(paise: bigint | string): string {
  const p = BigInt(paise);
  const abs = p < 0n ? -p : p;
  const whole = (abs / 100n).toString().replace(/(\d)(?=(\d\d)+\d$)/g, '$1,');
  return `${p < 0n ? '-' : ''}INR ${whole}.${String(abs % 100n).padStart(2, '0')}`;
}
