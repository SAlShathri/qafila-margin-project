-- Grain: one row per iso_week x city x category with at least one counted line.
with counted_lines as (
    -- rule 7: delivered, quantity > 0, on or after the first supplier week
    select
        o.order_date,
        s.city,
        p.category,
        p.sku,
        i.quantity,
        round(i.quantity * i.unit_price - i.discount, 2) as line_revenue   -- rule 8
    from {{ ref('stg_order_items') }} i
    join {{ ref('stg_orders') }} o        on o.order_id = i.order_id
    left join {{ ref('stg_products') }} p on p.product_id = i.product_id
    left join {{ ref('stg_stores') }} s   on s.store_id = o.store_id
    where o.status = 'delivered'
      and i.quantity > 0
      and o.order_date >= date '2026-08-31'
),

costed_lines as (
    -- rule 9: cost from the version valid on the order date (valid_to is exclusive)
    select
        l.*,
        l.quantity * h.unit_cost_sar as line_cost       -- null when no version is valid
    from counted_lines l
    left join {{ ref('product_cost_history') }} h
        on  h.sku = l.sku
        and h.valid_from <= l.order_date
        and (h.valid_to is null or l.order_date < h.valid_to)
)

select
    week(order_date)::int                                                    as iso_week,
    city,
    category,
    count(*)::int                                                            as lines,
    round(sum(line_revenue), 2)                                              as revenue_sar,
    round(coalesce(sum(line_revenue) filter (where line_cost is not null), 0), 2) as costed_revenue_sar,
    round(coalesce(sum(line_cost), 0), 2)                                    as cost_sar,
    round(costed_revenue_sar - cost_sar, 2)                                  as margin_sar,
    (count(*) filter (where line_cost is null))::int                         as uncosted_lines
from costed_lines
group by all