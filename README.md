# Qafila gross margin

Submitted by: Sarah AlShathri — academy: @SDAIAAcademy

## Design

```
SQLite app DB + supplier CSVs
        │  ingest()  (run.py)
        ▼
raw.*            exact copies, every column of the CSVs kept as text, plus source_file
        │  dbt
        ▼
staging.*        views: parse costs, trim SKUs, Riyadh order dates
silver.product_cost_history   SCD2, one row per SKU per cost version
quality.price_quarantine      one row per rejected supplier row
gold.weekly_margin            one row per iso_week × city × category
        │  publish()  (run.py)
        ▼
Iceberg (same three tables), overwritten in place on every run
```

**Key decisions**
- **Raw as text:** supplier files load with `all_varchar` and `union_by_name`, so `9,49`, Arabic digits and the renamed W39 column never break loading, and `raw_cost` stays exactly as written.
- **Idempotent landing:** `CREATE OR REPLACE` on every raw table, and one glob for all supplier files (no file names hard-coded).
- **Quarantine order:** unknown SKU is checked before invalid cost, and quarantined rows are excluded everywhere else.
- **Correction:** for the same SKU + `valid_from`, the file name that sorts last wins (`..._W39_fix.csv` > `..._W39.csv`).
- **SCD2:** a new version only when the cost changes (`lag`), `valid_to` = next `valid_from` (`lead`, exclusive).
- **Point-in-time join:** `valid_from <= order_date < valid_to` (or `valid_to` is null). Lines with no version count in `lines` and `revenue_sar` but not in cost.
- **Publish:** `create_table_if_not_exists` + `overwrite`, never drop, so older snapshots remain readable.

## Data problems found

| Source | Problem | Count | Handled in |
|---|---|---|---|
| W38 | Decimal commas (`9,49`) | 126 rows | `stg_supplier_prices` |
| W38 | Arabic-Indic digits (`٩٫٤٩`) | 34 rows | `stg_supplier_prices` |
| W38 | Byte-order mark | 1 file | DuckDB `read_csv` strips it |
| W39 | `unit_cost` renamed to `cost_sar`, columns reordered, `currency` added | 1 file (+ fix file) | `union_by_name` + `coalesce` |
| W39 | Zero or negative costs | 4 rows | quarantine `invalid_cost` |
| W39 | SKUs Qafila doesn't sell | 3 rows | quarantine `unknown_sku` |
| products | SKUs with trailing spaces | 2 | `trim` on both sides |
| order_items | Zero or negative quantities | 142 lines | excluded in `weekly_margin` |
| margin | Lines with no valid cost (mostly week 36, before most SKUs were quoted) | 20,626 of 82,404 | counted as `uncosted_lines` |

## Evidence

**Tests:** 11 dbt tests (8 generic, 3 singular), all passing. `tools/check.py`: 22/22 on the default data and on `--seed 11`.

**Re-run** (`tools/evidence.py` compares the last two data snapshots):
```
silver.product_cost_history: 6 versions, last two identical = True
gold.weekly_margin: 6 versions, last two identical = True
quality.price_quarantine: 6 versions, last two identical = True
```

**Correction and time travel:** total margin per snapshot of `gold.weekly_margin`
```
2026-10-22 07:50:44 UTC  snapshot 6399899851218219085: total margin = 801,016.88   (before fix)
2026-10-22 07:50:48 UTC  snapshot 7432100388661620508: total margin = 803,515.80   (after fix)
2026-10-22 07:54:45 UTC  snapshot 5609076928065105213: total margin = 803,515.80   (re-run)
```
The older snapshot still holds the pre-correction numbers.

Note: pyiceberg's `overwrite` commits two snapshots per run (one removing the old rows, then an `append`), so there are about twice as many snapshots as runs. The evidence script reads only the `append` snapshots.

## How I used AI
I used Claude as a step-by-step assistant: planning the steps, rewriting my code in a clear structured format, adding comments, and explaining errors. I ran every step myself, checked the outputs against the rules (row counts, quarantine reasons, SCD2 checks, `tools/check.py`), and fixed issues as they came up.