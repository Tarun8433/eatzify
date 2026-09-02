/**
 * Seeded PRNG. docs/04 §1: seed = hash(user_id + plan_date + packVersion), so food selection is
 * reproducible for a given user and date. `Math.random()` is forbidden in this package.
 */

/** FNV-1a, 32-bit. Stable across runs and platforms — that is the whole requirement. */
export function hashSeed(
  userId: string,
  planDate: string,
  packVersion: string,
): number {
  const input = `${userId}|${planDate}|${packVersion}`;
  let hash = 0x811c9dc5;
  for (let i = 0; i < input.length; i += 1) {
    hash ^= input.charCodeAt(i);
    hash = Math.imul(hash, 0x01000193);
  }
  return hash >>> 0;
}

/** mulberry32 — small, fast, and deterministic for a 32-bit seed. */
export function createPrng(seed: number): () => number {
  let state = seed >>> 0;
  return function next(): number {
    state = (state + 0x6d2b79f5) >>> 0;
    let t = state;
    t = Math.imul(t ^ (t >>> 15), t | 1);
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}
