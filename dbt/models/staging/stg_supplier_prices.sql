-- One row per supplier file row. Costs parsed; raw text kept for quarantine.
with src as (
    select
        source_file,
        trim(sku)                         as sku,
        valid_from::date                  as valid_from,
        coalesce(cost_sar, unit_cost)     as raw_cost   -- W39 renamed unit_cost to cost_sar
    from {{ source('raw', 'supplier_prices') }}
)
select
    *,
    -- '٩٫٤٩' and '9,49' both become 9.49; unparseable text becomes null
    try_cast(
        replace(translate(raw_cost, '٠١٢٣٤٥٦٧٨٩٫', '0123456789.'), ',', '.')
        as double
    ) as unit_cost_sar
from src