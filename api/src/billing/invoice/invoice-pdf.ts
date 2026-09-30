import PDFDocument from 'pdfkit';
import type { InvoiceEntity } from './invoice.entity';
import { inr } from './invoice-rules';

const MARGIN = 50;
const LABEL_WIDTH = 330;

/// One A4 page: seller, number and date, the line, and the tax split. No buyer name or address —
/// a B2C invoice under ₹50,000 does not need them, and the app holds none worth printing.
export function renderInvoicePdf(
  invoice: InvoiceEntity,
  original: InvoiceEntity | null,
): Promise<Buffer> {
  return new Promise((resolve, reject) => {
    const doc = new PDFDocument({ size: 'A4', margin: MARGIN });
    const chunks: Buffer[] = [];
    doc.on('data', (c: Buffer) => chunks.push(c));
    doc.on('end', () => resolve(Buffer.concat(chunks)));
    doc.on('error', reject);

    const credit = invoice.kind === 'credit_note';
    doc.fontSize(18).text(credit ? 'Credit Note' : 'Tax Invoice');
    doc.moveDown(0.5).fontSize(10);
    doc.text(invoice.sellerLegalName);
    doc.text(invoice.sellerAddress);
    doc.text(`GSTIN: ${invoice.sellerGstin}`);
    doc.moveDown();
    doc.text(`${credit ? 'Credit note' : 'Invoice'} no.: ${invoice.number}`);
    doc.text(`Date: ${invoice.issuedAt.toISOString().slice(0, 10)}`);
    if (original) {
      doc.text(
        `Against invoice: ${original.number} dated ${original.issuedAt.toISOString().slice(0, 10)}`,
      );
    }
    doc.text(`Place of supply: ${invoice.placeOfSupply}`);
    doc.moveDown();

    const row = (label: string, value: string) => {
      const y = doc.y;
      doc.text(label, MARGIN, y, { width: LABEL_WIDTH });
      doc.text(value, MARGIN + LABEL_WIDTH, y, { align: 'right' });
    };
    row(
      `${invoice.description} (SAC ${invoice.sacCode})`,
      inr(invoice.taxablePaise),
    );
    const rate = invoice.rateBps / 100;
    if (BigInt(invoice.igstPaise) > 0n) {
      row(`IGST @ ${rate}%`, inr(invoice.igstPaise));
    } else {
      row(`CGST @ ${rate / 2}%`, inr(invoice.cgstPaise));
      row(`SGST @ ${rate / 2}%`, inr(invoice.sgstPaise));
    }
    doc.moveDown(0.5).fontSize(12);
    row(credit ? 'Total credited' : 'Total paid', inr(invoice.totalPaise));
    doc.moveDown(2).fontSize(8);
    doc.text(
      'This is a computer-generated document and needs no signature.',
      MARGIN,
    );
    doc.end();
  });
}
