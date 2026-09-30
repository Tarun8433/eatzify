import { FindOperator } from 'typeorm';

export type Row = Record<string, unknown> & {
  id: string;
  userId: number;
  provider: string | null;
  providerRef: string | null;
  status: string;
};

/// An in-memory subscription table with just the queries the grant service makes.
export function table(rows: Row[] = []) {
  let n = rows.length;
  const repo = {
    rows,
    findOne: ({ where }: { where: Record<string, unknown> }) => {
      const match = rows.filter((r) =>
        Object.entries(where).every(([k, v]) => {
          if (v instanceof FindOperator) {
            return (v.value as unknown[]).includes(r[k]);
          }
          return r[k] === v;
        }),
      );
      return Promise.resolve(match[match.length - 1] ?? null);
    },
    save: (row: Row) => {
      const at = rows.findIndex((r) => r.id === row.id);
      const saved = { ...row, id: row.id ?? `s${++n}` };
      if (at >= 0) rows[at] = saved;
      else rows.push(saved);
      return Promise.resolve(saved);
    },
  };
  return repo;
}
