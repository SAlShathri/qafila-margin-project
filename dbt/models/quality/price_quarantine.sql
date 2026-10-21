-- Grain: one row per rejected supplier row.
-- unknown_sku is checked before invalid_cost.
with products as (
    select distinct sku from {{ ref('stg_products') }}
)
select
    sp.source_file,
    sp.sku,
    sp.valid_from,
    sp.raw_cost,
    case
        when p.sku is null then 'unknown_sku'
        else 'invalid_cost'
    end as reason
from {{ ref('stg_supplier_prices') }} sp
left join products p on p.sku = sp.sku
where p.sku is null
   or sp.unit_cost_sar is null
   or sp.unit_cost_sar <= 0