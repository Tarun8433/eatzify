import { mkdirSync, writeFileSync } from 'fs';
import { join, resolve } from 'path';

/// Builds `config/exercises/library-v1.json`, the exercise library the AddGym migration loads (D-244).
///
///   npx ts-node scripts/build-exercise-library.ts
///
/// The source is hasaneyldrm/exercises-dataset (MIT) at a pinned commit, so a rebuild is
/// reproducible. Only what the app uses is kept: names, body part, equipment, muscles, and the
/// English and Hindi steps. The dataset's media is © Gym visual and NOT under that licence (D-243), so
/// only its id is kept — enough to switch media on later without a migration, nothing more.
///
/// openGym (AGPL) ships its own conversion of this dataset. It is deliberately not the source here
/// (ADR-012): this reads upstream directly.

const COMMIT = '7455efae41b330c265e7cd4b78dfa848e7ce5ebd';
const SOURCE = `https://raw.githubusercontent.com/hasaneyldrm/exercises-dataset/${COMMIT}/data/exercises.json`;
const OUT_DIR = resolve('config/exercises');

type Upstream = {
  id: string;
  name: string;
  body_part: string;
  equipment: string;
  target: string;
  secondary_muscles?: string[];
  instruction_steps?: Record<string, string[]>;
  media_id?: string;
};

export type LibraryExercise = {
  id: string;
  name: string;
  body_part: string;
  equipment: string;
  target: string;
  secondary: string[];
  steps: { en: string[]; hi: string[] };
  media_id: string | null;
  energy_activity: string;
  is_bodyweight: boolean;
};

/// "45в°" is "45°" read through the wrong code page upstream.
export function cleanName(name: string): string {
  return name.replace(/в°/g, '°').trim();
}

/// Which `energy_reference.activity` prices a set of this exercise (D-242). Cardio is split by what
/// the machine or movement is, because a treadmill walk and a burpee are an order of magnitude
/// apart; everything else is resistance work, bodyweight or loaded.
export function energyActivityFor(
  e: Pick<Upstream, 'name' | 'body_part' | 'equipment'>,
): string {
  const name = e.name.toLowerCase();
  if (e.body_part !== 'cardio') {
    return e.equipment === 'body weight' ? 'calisthenics' : 'strength';
  }
  // Machine first: "stationary bike run" is a bike, not a run.
  if (/bike/.test(name) || e.equipment === 'stationary bike')
    return 'stationary_bike';
  if (/elliptical|cross trainer/.test(name)) return 'elliptical';
  if (/stepmill/.test(name)) return 'stair_treadmill';
  if (/treadmill/.test(name)) return 'walk';
  // "Wheel run" is an ab-wheel rollout by its own steps — a floor move, not a run.
  if (/\brun\b|jog/.test(name) && !/wheel/.test(name)) return 'run';
  if (/jump rope/.test(name)) return 'rope_skipping';
  return 'calisthenics_vigorous';
}

export function toLibrary(rows: Upstream[]): LibraryExercise[] {
  return rows
    .map((e) => ({
      id: e.id,
      name: cleanName(e.name),
      body_part: e.body_part,
      equipment: e.equipment,
      target: e.target,
      secondary: [...new Set(e.secondary_muscles ?? [])],
      steps: {
        en: e.instruction_steps?.en ?? [],
        hi: e.instruction_steps?.hi ?? [],
      },
      media_id: e.media_id ?? null,
      energy_activity: energyActivityFor(e),
      is_bodyweight: e.equipment === 'body weight',
    }))
    .sort((a, b) => a.id.localeCompare(b.id));
}

const NOTICE = `# Exercise library — third-party notice

\`library-v1.json\` is derived from **hasaneyldrm/exercises-dataset**
(https://github.com/hasaneyldrm/exercises-dataset), commit \`${COMMIT}\`, used under the MIT
License below. It keeps the names, body part, equipment, target and secondary muscles, and the
English and Hindi instruction steps. \`energy_activity\` and \`is_bodyweight\` are added by
\`scripts/build-exercise-library.ts\`.

The dataset's images and animations are **© Gym visual — https://gymvisual.com/** and are NOT
covered by the MIT License. None are included here. \`media_id\` only names them; serving them
needs a licence from Gym visual (D-243).

\`\`\`
MIT License

Copyright (c) 2026 Hasan Emir Yıldırım

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation and data files (the "Software"),
to deal in the Software without restriction, including without limitation the
rights to use, copy, modify, merge, publish, distribute, sublicense, and/or
sell copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
\`\`\`
`;

async function main(): Promise<void> {
  const response = await fetch(SOURCE);
  if (!response.ok)
    throw new Error(`fetch failed: ${response.status} ${SOURCE}`);
  const library = toLibrary((await response.json()) as Upstream[]);

  mkdirSync(OUT_DIR, { recursive: true });
  writeFileSync(join(OUT_DIR, 'library-v1.json'), JSON.stringify(library));
  writeFileSync(join(OUT_DIR, 'NOTICE.md'), NOTICE);
  console.log(`wrote ${library.length} exercises to ${OUT_DIR}`);
}

if (require.main === module) {
  main().catch((error: unknown) => {
    console.error(error);
    process.exit(1);
  });
}
