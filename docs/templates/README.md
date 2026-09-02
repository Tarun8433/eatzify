# Food import template

Fill `foods-template.csv` in any spreadsheet, export as CSV, and upload:

```
POST /api/v1/foods/import      (admin only, multipart: file=<your.csv>)
```

## Rules the importer enforces

Nothing is imported if **any** row fails — you get a list of problems with row numbers, fix them,
and upload again. A partially-imported food database is worse than an empty one, because you cannot
tell which half is real.

| Column | Notes |
|---|---|
| `name` | Required. Re-importing the same name **updates** that food. |
| `kcal` `proteinG` `fatG` `carbG` | Required. **Per 100 g edible portion** (docs/03) — never per serving. |
| `tags` | `\|`-separated. Must start with `gi:`, `attr:`, `meal:` or `cuisine:`. These strings are matched by the rule pack, so a typo silently drops the food from a medical constraint. |
| `suitableFor` | `\|`-separated. At least one of `veg`, `non_veg`, `eggetarian`, `jain`, `vegan`. |
| `allergens` | `\|`-separated. **Be exhaustive** — this drives exclusion, so an unlisted peanut reaches a peanut-allergic user. |
| `source` | Required. `IFCT2017`, `INDB`, or `manual`. docs/03: a number nobody can attribute cannot be corrected. |
| `aliases` | `\|`-separated, what people actually **type**: `chapati\|phulka` for roti, `maggi` for instant noodles, `golgappa` for pani puri. Search matches these alongside both names. A food nobody can find is a food nobody logs, and an unlogged meal is a hole in the diary — not a neutral absence. |
| `measures` | `katori=150\|roti=35*` — `*` marks the default. docs/03 calls these non-negotiable for India; users think in katoris, not grams. |

## Checks that will reject a row

- Macros exceeding 100 g per 100 g portion.
- `kcal` disagreeing with the macros by more than 25 % (4/4/9 kcal per gram). This catches a column
  typed into the wrong field, which is the most common spreadsheet error.
- Any tag, allergen, preference or cost tier outside the allowed vocabulary.

## Two mistakes that cost time on the first real import

- **`costTier` is `low` / `medium` / `premium`** — not `high`. The word `high` is legal inside
  `tags` (`gi:high`, `attr:high_fibre`), which makes a blind find-and-replace across the file
  destructive. Fix the column, not the text.
- **An unrecognised column is rejected, not ignored.** A seed file used `satFatG`; had that been
  accepted it would have imported as a silent `0`, and saturated fat feeds the docs/05 constraint
  set. The header must match this document exactly.

## Imported foods are not live yet

Rows arrive with `isVerified = false` and are excluded from search and plan generation until an
admin verifies them. A half-entered food must never reach a user's plan.
