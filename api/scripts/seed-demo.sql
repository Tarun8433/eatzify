-- Demo data for the signed-in dev user (id 62, +916767768966), so Home's past days and the
-- whole Progress dashboard render with real content. Idempotent: re-running first clears the
-- seeded diary window and skips measurement days that already exist. Today (2026-09-01) is
-- left entirely alone — those are real logs.

BEGIN;

-- ── Diary: 14 days of meals, 2026-08-18 .. 2026-08-31 ────────────────────────────────────────
DELETE FROM food_log
WHERE "userId" = 62 AND "diaryDate" BETWEEN '2026-08-18' AND '2026-08-31';

WITH days AS (
  SELECT gs::date AS d, extract(day FROM gs)::int AS n
  FROM generate_series(date '2026-08-18', date '2026-08-31', interval '1 day') gs
),
-- cond: 0..3 = day-of-month % 4 rotation · -1 even days · -2 odd days · -3 every 3rd · -9 daily
menu(slot, food_name, qty, label, tod, cond) AS (VALUES
  ('breakfast',   'Idli',                  180, 'piece',  '08:30', 0),
  ('breakfast',   'Masala dosa',           150, 'piece',  '08:30', 1),
  ('breakfast',   'Daliya (cooked)',       220, 'katori', '08:30', 2),
  ('breakfast',   'Egg bhurji',            120, 'katori', '08:30', 3),
  ('mid_morning', 'Banana',                100, 'piece',  '11:00', -2),
  ('mid_morning', 'Buttermilk (chaas)',    200, 'glass',  '11:00', -1),
  ('lunch',       'Roti (whole wheat)',     90, 'piece',  '13:30', -9),
  ('lunch',       'Dal tadka',             150, 'katori', '13:30', -9),
  ('lunch',       'Bhindi masala',         100, 'katori', '13:30', -9),
  ('snack',       'Apple',                 150, 'piece',  '17:00', -3),
  ('dinner',      'Khichdi (moong dal)',   220, 'katori', '20:00', -1),
  ('dinner',      'Chicken curry',         150, 'katori', '20:00', -2),
  ('dinner',      'Basmati rice (cooked)', 150, 'katori', '20:00', -2)
)
INSERT INTO food_log
  ("userId", "diaryDate", slot, "foodId", "quantityG", "measureLabel",
   kcal, "proteinG", "carbG", "fatG", "fibreG", source, "loggedAt")
SELECT
  62, days.d, menu.slot, f.id, v.g, menu.label,
  round(f.kcal      * v.g / 100, 1),
  round(f."proteinG" * v.g / 100, 1),
  round(f."carbG"    * v.g / 100, 1),
  round(f."fatG"     * v.g / 100, 1),
  round(f."fibreG"   * v.g / 100, 1),
  'manual',
  days.d + menu.tod::time
FROM days
JOIN menu ON (
     (menu.cond >= 0 AND days.n % 4 = menu.cond)
  OR (menu.cond = -1 AND days.n % 2 = 0)
  OR (menu.cond = -2 AND days.n % 2 = 1)
  OR (menu.cond = -3 AND days.n % 3 = 0)
  OR  menu.cond = -9
)
JOIN food f ON f.name = menu.food_name
-- portion drifts a little day to day so the calorie bars vary like a real week
CROSS JOIN LATERAL (SELECT (menu.qty + (days.n % 3) * 15)::numeric AS g) v;

-- ── Weight: every 2nd day for a month, drifting 74.8 → ~72.5 kg ──────────────────────────────
INSERT INTO measurement ("userId", kind, value, unit, "diaryDate", source, "isSuspect", "recordedAt")
SELECT 62, 'weight',
       round((74.8 - i * 0.15 + sin(i) * 0.12)::numeric, 1), 'kg',
       date '2026-08-02' + i * 2, 'manual', false,
       (date '2026-08-02' + i * 2) + time '07:30'
FROM generate_series(0, 15) i
ON CONFLICT ("userId", kind, "diaryDate") DO NOTHING;

-- ── Daily habits: steps, water, calories burned, 2026-08-18 .. 2026-08-31 ────────────────────
INSERT INTO measurement ("userId", kind, value, unit, "diaryDate", source, "isSuspect", "recordedAt")
SELECT 62, h.kind, h.base + (i * h.step) % h.spread, h.unit,
       date '2026-08-18' + i, 'manual', false,
       (date '2026-08-18' + i) + time '21:00'
FROM generate_series(0, 13) i
CROSS JOIN (VALUES
  ('steps',              'steps', 4200, 937, 6800),
  ('water_ml',           'ml',    1500, 613, 1200),
  ('energy_burned_kcal', 'kcal',   240, 211,  380)
) AS h(kind, unit, base, step, spread)
ON CONFLICT ("userId", kind, "diaryDate") DO NOTHING;

-- ── Body measurements: a few readings over the month ─────────────────────────────────────────
INSERT INTO measurement ("userId", kind, value, unit, "diaryDate", source, "isSuspect", "recordedAt")
VALUES
  (62, 'waist', 88.4, 'cm', '2026-08-05', 'manual', false, timestamp '2026-08-05 08:00'),
  (62, 'waist', 87.8, 'cm', '2026-08-19', 'manual', false, timestamp '2026-08-19 08:00'),
  (62, 'waist', 87.2, 'cm', '2026-08-29', 'manual', false, timestamp '2026-08-29 08:00'),
  (62, 'hip',   98.6, 'cm', '2026-08-05', 'manual', false, timestamp '2026-08-05 08:00'),
  (62, 'hip',   97.9, 'cm', '2026-08-29', 'manual', false, timestamp '2026-08-29 08:00'),
  (62, 'chest', 96.2, 'cm', '2026-08-05', 'manual', false, timestamp '2026-08-05 08:00'),
  (62, 'chest', 95.8, 'cm', '2026-08-29', 'manual', false, timestamp '2026-08-29 08:00'),
  (62, 'thigh', 55.4, 'cm', '2026-08-05', 'manual', false, timestamp '2026-08-05 08:00'),
  (62, 'thigh', 54.9, 'cm', '2026-08-29', 'manual', false, timestamp '2026-08-29 08:00')
ON CONFLICT ("userId", kind, "diaryDate") DO NOTHING;

COMMIT;

-- What landed, day by day
SELECT "diaryDate", count(*) AS entries, round(sum(kcal)) AS kcal
FROM food_log WHERE "userId" = 62 GROUP BY 1 ORDER BY 1;
