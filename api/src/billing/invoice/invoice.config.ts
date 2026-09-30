import { registerAs } from '@nestjs/config';
import { IsOptional, IsString, Matches } from 'class-validator';
import validateConfig from '../../utils/validate-config';

/// GST tax invoices for what Eatzify sells directly (Cashfree). All optional: with no GSTIN the
/// business is not registered, and no invoice is issued — a receipt is not a tax invoice, and
/// issuing one while unregistered would be wrong. Every value here comes from the CA.
export type InvoiceConfig = {
  sellerGstin: string | null;
  sellerLegalName: string | null;
  sellerAddress: string | null;
  /// The two-digit GST state code of the seller (e.g. `07` Delhi). Decides CGST+SGST vs IGST.
  sellerStateCode: string | null;
  /// Services Accounting Code for the subscription, as the CA classifies it.
  sacCode: string | null;
  /// Key for the sealed partner KYC columns (32 bytes, base64). See `utils/field-crypto.ts`.
  kycFieldKey: string | null;
};

class InvoiceEnvValidator {
  @Matches(/^[0-9]{2}[A-Z0-9]{13}$/)
  @IsOptional()
  GST_SELLER_GSTIN: string;

  @IsString()
  @IsOptional()
  GST_SELLER_LEGAL_NAME: string;

  @IsString()
  @IsOptional()
  GST_SELLER_ADDRESS: string;

  @Matches(/^[0-9]{2}$/)
  @IsOptional()
  GST_SELLER_STATE_CODE: string;

  @Matches(/^[0-9]{6}$/)
  @IsOptional()
  GST_SAC_CODE: string;

  @IsString()
  @IsOptional()
  KYC_FIELD_KEY: string;
}

export default registerAs<InvoiceConfig>('invoice', () => {
  validateConfig(process.env, InvoiceEnvValidator);
  return {
    sellerGstin: process.env.GST_SELLER_GSTIN || null,
    sellerLegalName: process.env.GST_SELLER_LEGAL_NAME || null,
    sellerAddress: process.env.GST_SELLER_ADDRESS || null,
    sellerStateCode: process.env.GST_SELLER_STATE_CODE || null,
    sacCode: process.env.GST_SAC_CODE || null,
    kycFieldKey: process.env.KYC_FIELD_KEY || null,
  };
});
