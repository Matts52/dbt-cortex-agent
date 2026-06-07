{{ config(materialized='table') }}

select
    order_id,
    region,
    amount
from {{ ref('orders_seed') }}
