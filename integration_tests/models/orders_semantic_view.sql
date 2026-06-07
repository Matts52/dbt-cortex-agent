{{ config(materialized='semantic_view') }}
TABLES(orders AS {{ ref('orders_base') }})
DIMENSIONS(orders.region AS region)
METRICS(orders.total_amount AS SUM(orders.amount))
COMMENT='Orders semantic view for the integration-test agent'
