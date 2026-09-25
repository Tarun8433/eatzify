import { createHmac, randomUUID, timingSafeEqual } from 'node:crypto';
import { mkdir, readdir, stat, unlink, writeFile } from 'node:fs/promises';
import { basename, join, resolve } from 'node:path';

/// D-240. Where a user's own meal photos live, and the only way they are ever served.
///
/// Outside `./files` on purpose: the local file driver serves that folder to anyone with a path.
/// These are photographs of what a person eats, kept private (docs/13 §4) — they leave the server
/// only through a signed link that names one entry and expires, the local stand-in for the R2
/// presigned URLs D-22 requires in production.

export const mealPhotoDir = (): string =>
  resolve(process.env.MEAL_PHOTO_DIR ?? 'files-private/meal-photos');

/// How long a link works. Long enough for a screen to load and cache the photo, short enough that
/// a copied link is soon useless.
const linkTtlSeconds = (): number =>
  Number(process.env.MEAL_PHOTO_LINK_TTL_SECONDS ?? 3600);

/// A new photo's file name, relative to [mealPhotoDir]. Readable by this process only.
export async function saveMealPhoto(
  image: Buffer,
  ext: 'jpg' | 'png',
): Promise<string> {
  await mkdir(mealPhotoDir(), { recursive: true });
  const name = `${randomUUID()}.${ext}`;
  await writeFile(join(mealPhotoDir(), name), image, { mode: 0o600 });
  return name;
}

/// Deleting a photo that is already gone is not an error — the sweep and an undo can race.
export async function deleteMealPhoto(name: string): Promise<void> {
  try {
    await unlink(join(mealPhotoDir(), basename(name)));
  } catch (e) {
    if ((e as NodeJS.ErrnoException).code !== 'ENOENT') throw e;
  }
}

/// Every stored photo and when it was written — for the sweep's orphan pass.
export async function listMealPhotos(): Promise<
  { name: string; modified: Date }[]
> {
  let names: string[];
  try {
    names = await readdir(mealPhotoDir());
  } catch (e) {
    if ((e as NodeJS.ErrnoException).code === 'ENOENT') return [];
    throw e;
  }
  return Promise.all(
    names.map(async (name) => ({
      name,
      modified: (await stat(join(mealPhotoDir(), name))).mtime,
    })),
  );
}

const secret = (): string => {
  const s = process.env.AUTH_JWT_SECRET;
  if (!s) throw new Error('AUTH_JWT_SECRET is not set');
  return s;
};

const signature = (logId: string, exp: number): string =>
  createHmac('sha256', secret())
    .update(`meal-photo:${logId}:${exp}`)
    .digest('base64url');

/// The entry's photo link, relative to the API like the food photos (D-83). Signed for this one
/// entry and this expiry, so it cannot be edited into another entry's photo.
export function signedPhotoPath(logId: string, now = Date.now()): string {
  const exp = Math.floor(now / 1000) + linkTtlSeconds();
  return `/logs/food/${logId}/photo?exp=${exp}&sig=${signature(logId, exp)}`;
}

export function verifyPhotoLink(
  logId: string,
  exp: string | undefined,
  sig: string | undefined,
  now = Date.now(),
): boolean {
  const expiry = Number(exp);
  if (!Number.isInteger(expiry) || expiry * 1000 < now || !sig) return false;
  const expected = Buffer.from(signature(logId, expiry));
  const given = Buffer.from(sig);
  return expected.length === given.length && timingSafeEqual(expected, given);
}
