import { createCipheriv, createDecipheriv, randomBytes } from 'crypto';

/// AES-256-GCM for a handful of columns that must be readable by a person later but must not sit
/// in the database in clear (a partner's full PAN and bank account). The key is 32 bytes, base64,
/// from the environment — never in the database it protects.
///
/// Format: `v1.<iv>.<tag>.<ciphertext>`, each base64. The version lets the key rotate later.

const ALGORITHM = 'aes-256-gcm';
const IV_BYTES = 12;

function keyFrom(keyB64: string): Buffer {
  const key = Buffer.from(keyB64, 'base64');
  if (key.length !== 32) throw new Error('field key must be 32 bytes, base64');
  return key;
}

export function encryptField(plain: string, keyB64: string): string {
  const iv = randomBytes(IV_BYTES);
  const cipher = createCipheriv(ALGORITHM, keyFrom(keyB64), iv);
  const body = Buffer.concat([cipher.update(plain, 'utf8'), cipher.final()]);
  return ['v1', iv, cipher.getAuthTag(), body]
    .map((p) => (typeof p === 'string' ? p : p.toString('base64')))
    .join('.');
}

export function decryptField(sealed: string, keyB64: string): string {
  const [version, iv, tag, body] = sealed.split('.');
  if (version !== 'v1' || !iv || !tag || !body) {
    throw new Error('not a sealed field');
  }
  const decipher = createDecipheriv(
    ALGORITHM,
    keyFrom(keyB64),
    Buffer.from(iv, 'base64'),
  );
  decipher.setAuthTag(Buffer.from(tag, 'base64'));
  return Buffer.concat([
    decipher.update(Buffer.from(body, 'base64')),
    decipher.final(),
  ]).toString('utf8');
}
