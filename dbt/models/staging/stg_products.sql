-- One row per product. Two SKUs have trailing spaces.
select product_id, trim(sku) as sku, category
from {{ source('raw', 'products') }}