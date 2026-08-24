# eatzify-api

NestJS REST API for Eatzify. Specs live in `../docs/` — read the governing doc before implementing.

## What is built

| Path | Status |
|---|---|
| `packages/diet-engine/` | **Done.** Pure engine, docs/04 pipeline steps 1–10 + 12. 87 tests, 99.7 % stmt / 96 % branch coverage. |
| `config/rule-packs/v1.0.0.yaml` | **Done.** Every constant from docs/04 + docs/05. Needs clinical sign-off. |
| `src/modules/engine/` | **Done.** Loader + zod schema + `EngineService`. Validates the pack at boot. |
| `src/modules/{auth,profile,plans,food,logs,coach,partner,billing,notify,consent,audit}/` | Not started — docs/06 §2 defines the boundaries. |

Engine pipeline steps 11, 13 and 14 (candidate pool, greedy fill, alternates) need the food
database, which docs/20 §1 and §6 say has to be built by hand. `distributeMeals` emits per-slot
targets; nothing fakes food items.

```bash
npm run test:engine        # 87 engine tests
npx jest                   # loader + EngineService tests
npx ts-node scripts/validate-rule-packs.ts   # boot-equivalent pack check, wire into CI
```

## The rest of src/ is not here yet — on purpose

Per `../docs/20-foundations-boilerplates.md` §2 and §10 step 1, the application skeleton comes from a
pruned fork of `brocoders/nestjs-boilerplate` (MIT), not hand-written. Run these from `api/`:

```bash
git clone --depth 1 https://github.com/brocoders/nestjs-boilerplate .boilerplate-tmp
rm -r .boilerplate-tmp/.git
```

**Prune before importing.** Doc 20 §2: *"A boilerplate you haven't pruned becomes a codebase you
don't understand."* Each removal below is a decision, not tidying:

| Remove | Why |
|---|---|
| `src/**/document/`, `src/**/mongoose/`, `**/*.schema.ts` | Postgres-only — ADR-003 |
| `src/auth-apple/` `auth-facebook/` `auth-google/` `auth-twitter/` | Phone OTP is primary auth in India |
| `src/home/`, `test/home/` | Example module — nothing here is Eatzify |

```bash
# from .boilerplate-tmp, after reading the table above
rm -r src/auth-apple src/auth-facebook src/auth-google src/auth-twitter src/home test/home
find src -type d \( -name document -o -name mongoose \) -prune -exec rm -r {} +
find src -type f -name '*.schema.ts' -delete
```

Then import **without overwriting** what already exists here — `src/modules/engine/`,
`config/rule-packs/` and `packages/` are ours and must survive:

```bash
cp -Rn .boilerplate-tmp/src/.  src/          # -n = never clobber
cp -Rn .boilerplate-tmp/test/. test/
cp -Rn .boilerplate-tmp/.github/. .github/
for f in docker-compose.yml Dockerfile eslint.config.mjs .prettierrc nest-cli.json; do
  [ -e ".boilerplate-tmp/$f" ] && [ ! -e "$f" ] && cp ".boilerplate-tmp/$f" "$f"
done
rm -r .boilerplate-tmp
```

**Reconcile `package.json` by merging, never overwriting** — ours pins the doc 20 §8 set plus the
workspace link to `@eatzify/diet-engine`. Then:

```bash
npm install
ls src/modules/engine config/rule-packs packages/diet-engine   # all three must still be here
npm run test:engine    # expect 87 passed
npx jest               # expect 15 passed
```

If you later re-add social sign-in, record it in `../docs/DECISIONS.md` rather than silently.

`package.json` here already pins the dependency set from doc 20 §8 — reconcile it with the
boilerplate's own manifest rather than overwriting it.

## Before the first commit

- `cp .env.example .env` and fill it in. `.env` is gitignored and Read-denied in `.claude/settings.json`.
- Configure `nestjs-pino` redaction **on day one** — the exact `redact.paths` list is in doc 20 §8.
  That is the mechanical half of hard rule 5 (no PII in logs).
- `config/rule-packs/` is Edit-denied by design. See `config/rule-packs/README.md`.

## Layout this repo's tooling expects

Path-scoped rules in the monorepo's root `.claude/rules/` fire on these paths:

| Path | Rule |
|---|---|
| `api/src/**/*.{controller,dto,service}.ts` | `api-conventions.md` |
| `api/src/**/*.entity.ts`, `api/src/migrations/**` | `database.md` |
| `api/src/modules/{billing,partner}/**` | `billing.md` |
| `api/packages/diet-engine/**`, `api/config/rule-packs/**` | `engine.md` |
| `api/**/*.spec.ts`, `api/**/*.e2e-spec.ts` | `api-testing.md` |

Slash commands: `/impl-endpoint`, `/engine-change`, `/schema-change`, `/safety-review`.
