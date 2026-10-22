select * from {{ ref('weekly_margin') }}
where abs(margin_sar - (costed_revenue_sar - cost_sar)) > 0.01
   or uncosted_lines > lines
   or costed_revenue_sar > revenue_sar + 0.01