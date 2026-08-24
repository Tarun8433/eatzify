# Where every file goes — Eatzify (Node backend + Flutter app)

> **This repo took the monorepo path** (see "Monorepo alternative" below), with one difference:
> Flutter sits at the repo root rather than under `apps/mobile/`, because the Flutter project was
> already there. The backend is `api/`. Scoping is done entirely by path-scoped `.claude/rules/`
> plus a nested `api/CLAUDE.md` — there is no second `.claude/` directory, since `settings.json`
> permissions are only enforced at the project root.

Two repos. The docs live in one place. Each repo gets its own `CLAUDE.md` and `.claude/`.

```
eatzify-api/                                 eatzify-app/
├── CLAUDE.md              ← backend scope    ├── CLAUDE.md              ← Flutter scope
├── docs/                  ← SOURCE OF TRUTH  ├── docs/                  ← submodule → eatzify-docs
│   ├── 00-research-findings.md               ├── lib/
│   ├── … 19-open-questions.md                ├── test/
├── .mcp.json              ← project root!    ├── .mcp.json
├── .claude/                                  ├── .claude/
│   ├── settings.json      committed          │   ├── settings.json
│   ├── settings.local.json  GITIGNORED       │   ├── settings.local.json  GITIGNORED
│   ├── rules/             path-scoped        │   ├── rules/
│   │   ├── api-conventions.md                │   │   ├── flutter-architecture.md
│   │   ├── engine.md                         │   │   ├── controllers.md
│   │   ├── database.md                       │   │   ├── ui-standards.md
│   │   ├── billing.md                        │   │   └── testing.md
│   │   └── testing.md                        │   ├── skills/
│   ├── skills/            /slash commands    │   │   ├── new-screen/SKILL.md
│   │   ├── impl-endpoint/SKILL.md            │   │   ├── new-feature/SKILL.md
│   │   ├── engine-change/SKILL.md            │   │   └── audit-fix/SKILL.md
│   │   ├── schema-change/SKILL.md            │   └── agents/
│   │   └── safety-review/                    │       └── flutter-reviewer.md
│   │       ├── SKILL.md                      ├── config/  (nothing Claude-specific)
│   │       └── checklist.md                  └── pubspec.yaml
│   └── agents/
│       └── code-reviewer.md
├── config/rule-packs/     ← engine constants
├── packages/diet-engine/
└── src/
```

## The three rules that decide placement

1. **`CLAUDE.md` at the repo root, not in `.claude/`.** Both work, but root is the convention and it
   loads every session. Keep it under ~200 lines — longer files still load but adherence drops. Anything
   that only matters for *some* tasks belongs in `rules/` or a skill, not here.

2. **`docs/` is not Claude config.** It's project documentation that happens to be written for Claude.
   It goes in the repo tree, versioned with the code. Do **not** put it inside `.claude/`.

3. **Enforcement vs guidance.** `CLAUDE.md` and `rules/` are advice Claude may or may not follow.
   `settings.json` permissions and hooks are enforced by Claude Code regardless. Put "never commit a
   secret" in permissions, not in prose.

## Sharing `docs/` between the two repos

Keep the full set in `eatzify-api` (that's where the engine, schema and API spec belong), then:

```bash
cd eatzify-app
git submodule add git@github.com:you/eatzify-docs.git docs
```

Or split `docs/` into its own repo and submodule it into both. What you must not do is copy the
markdown into both repos — they diverge inside a month, and then Claude reads whichever copy the
session happens to open.

If you'd rather avoid submodules: keep `docs/` only in the API repo, and in the app repo's `CLAUDE.md`
point at the four docs that matter to Flutter (02, 03, 14, 15) with a note to ask you for them.

## Monorepo alternative

If you'd rather keep one repo:

```
eatzify/
├── CLAUDE.md                  ← shared hard rules only
├── docs/
├── .claude/settings.json      ← shared permissions + hooks
├── .claude/rules/             ← path-scoped: backend rules fire on apps/api/**, Flutter on apps/mobile/**
├── apps/api/CLAUDE.md         ← nearest-file wins for backend work
└── apps/mobile/CLAUDE.md      ← nearest-file wins for Flutter work
```

Claude Code loads the root `CLAUDE.md` plus the nearest one to the files in context, so nested
`CLAUDE.md` files are the clean way to scope. Path-scoped `rules/` achieve the same thing without
nesting. Trade-off: a monorepo means one release train — with a Flutter app on Play's staged rollout
and a backend you deploy several times a week, two repos is usually less friction.

## `.gitignore` additions (both repos)

```
.claude/settings.local.json
CLAUDE.local.md
```

Claude Code adds `**/.claude/settings.local.json` to your global git excludes when it first writes
there, but add it to the project `.gitignore` too so your team gets the rule.

## What is NOT in `.claude/`

| File | Location | Why |
|---|---|---|
| `.mcp.json` | repo root | Project-scoped MCP servers live at the root, not in `.claude/` |
| `CLAUDE.local.md` | repo root, gitignored | Your personal per-project notes |
| `docs/` | repo tree | Project documentation |
| `config/rule-packs/*.yaml` | repo tree | Engine constants — application data, code-reviewed |
| Personal preferences | `~/.claude/CLAUDE.md` | Applies to every project you touch; never committed |

## Global config worth setting once (`~/.claude/`)

Your own `~/.claude/CLAUDE.md` — response style, commit format, the fact that you work on a Mac.
Keep it short: it loads alongside every project's `CLAUDE.md`.

## Order of installation

```bash
# 1. backend repo
cp -r eatzify-api/CLAUDE.md eatzify-api/.claude  <your-api-repo>/
cp -r eatzify-docs/docs                          <your-api-repo>/

# 2. app repo
cp -r eatzify-app/CLAUDE.md eatzify-app/.claude   <your-app-repo>/

# 3. both
echo ".claude/settings.local.json" >> .gitignore
echo "CLAUDE.local.md"             >> .gitignore
git add CLAUDE.md .claude && git commit -m "chore: add Claude Code project config"

# 4. verify
claude          # then run /memory to confirm CLAUDE.md loaded, and / to see the skills
```
