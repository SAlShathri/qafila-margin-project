"""Evidence for the README: re-runs and the correction, read from Iceberg snapshots.

Each overwrite in pyiceberg commits two snapshots: one that removes the old rows,
then an 'append' that writes the new rows. Only the 'append' snapshots hold a full
version of the table, so those are the ones compared here.

    uv run python tools/evidence.py
"""
from datetime import datetime, timezone
from pathlib import Path
import sys

import polars as pl

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from run import get_catalog

TABLES = ["silver.product_cost_history", "gold.weekly_margin", "quality.price_quarantine"]


def data_snapshots(table):
    """Snapshots that hold a full version of the table (the 'append' half of each overwrite)."""
    return [s for s in table.snapshots() if s.summary.operation.value == "append"]


def read(table, snapshot) -> pl.DataFrame:
    df = pl.from_arrow(table.scan(snapshot_id=snapshot.snapshot_id).to_arrow())
    return df.sort(df.columns)


catalog = get_catalog(Path("warehouse"))

print("1. Last two versions of each table")
for name in TABLES:
    table = catalog.load_table(name)
    snaps = data_snapshots(table)
    if len(snaps) < 2:
        print(f"   {name}: only {len(snaps)} version, run the pipeline again")
        continue
    before, after = read(table, snaps[-2]), read(table, snaps[-1])
    print(f"   {name}: {len(snaps)} versions, last two identical = {before.equals(after)}")

print("\n2. Total margin in every version of gold.weekly_margin (time travel)")
margin = catalog.load_table("gold.weekly_margin")
for s in data_snapshots(margin):
    committed = datetime.fromtimestamp(s.timestamp_ms / 1000, tz=timezone.utc).strftime("%Y-%m-%d %H:%M:%S UTC")
    total = read(margin, s)["margin_sar"].sum()
    print(f"   {committed}  snapshot {s.snapshot_id}: total margin = {total:,.2f}")