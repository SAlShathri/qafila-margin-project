-- Grain: one row per SKU per cost version (SCD2).
with valid_rows as (
    -- rows that pass quarantine (same rules, inverted)
    select sp.source_file, sp.sku, sp.valid_from, round(sp.unit_cost_sar, 2) as unit_cost_sar
    from {{ ref('stg_supplier_prices') }} sp
    where sp.sku in (select sku from {{ ref('stg_products') }})
      and sp.unit_cost_sar > 0
),

latest_quote as (
    -- same SKU + valid_from in several files: the file name that sorts last wins
    select *
    from valid_rows
    qualify row_number() over (partition by sku, valid_from order by source_file desc) = 1
),

with_previous as (
    select *, lag(unit_cost_sar) over (partition by sku order by valid_from) as previous_cost
    from latest_quote
),

versions as (
    -- a new version starts only when the cost changes
    select sku, unit_cost_sar, valid_from
    from with_previous
    where previous_cost is null or unit_cost_sar <> previous_cost
)

select
    sku,
    unit_cost_sar,
    valid_from,
    lead(valid_from) over (partition by sku order by valid_from) as valid_to,   -- exclusive
    lead(valid_from) over (partition by sku order by valid_from) is null as is_current
from versions