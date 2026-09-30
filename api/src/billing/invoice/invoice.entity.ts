import { BaseEntity, Column, Entity, PrimaryGeneratedColumn } from 'typeorm';
import type { InvoiceKind } from './invoice-rules';

/// A GST tax invoice or credit note (D-255). Written once, never edited: a correction is a credit
/// note that refers to the invoice. The seller's details are copied in, so a later change of
/// address does not rewrite an invoice already issued.
@Entity({ name: 'invoice' })
export class InvoiceEntity extends BaseEntity {
  @PrimaryGeneratedColumn('uuid')
  id: string;

  @Column({ type: 'text' })
  number: string;

  @Column({ type: 'text' })
  kind: InvoiceKind;

  @Column({ type: 'text' })
  fiscalYear: string;

  @Column()
  userId: number;

  @Column({ type: 'uuid' })
  paymentOrderId: string;

  @Column({ type: 'uuid', nullable: true })
  refersToId: string | null;

  @Column({ type: 'timestamptz' })
  issuedAt: Date;

  @Column({ type: 'text' })
  description: string;

  @Column({ type: 'text' })
  sacCode: string;

  @Column({ type: 'text' })
  sellerGstin: string;

  @Column({ type: 'text' })
  sellerLegalName: string;

  @Column({ type: 'text' })
  sellerAddress: string;

  @Column({ type: 'text' })
  sellerStateCode: string;

  @Column({ type: 'text' })
  placeOfSupply: string;

  @Column({ type: 'integer' })
  rateBps: number;

  /// BIGINT paise as strings (api rule 3).
  @Column({ type: 'bigint' })
  taxablePaise: string;

  @Column({ type: 'bigint' })
  cgstPaise: string;

  @Column({ type: 'bigint' })
  sgstPaise: string;

  @Column({ type: 'bigint' })
  igstPaise: string;

  @Column({ type: 'bigint' })
  totalPaise: string;
}
