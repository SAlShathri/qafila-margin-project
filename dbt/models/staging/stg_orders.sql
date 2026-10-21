-- One row per order. created_at is UTC text; business date is Riyadh (UTC+3).
select
    order_id,
    store_id,
    status,
    (created_at::timestamp + interval 3 hour)::date as order_date
from {{ source('raw', 'orders') }}