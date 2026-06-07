-- Verifies the dbt-managed semantic view (the agent's data source) is queryable
-- and consistent with its base table. Returns rows only on failure.
with from_semantic_view as (
    select sum(total_amount) as total
    from semantic_view(
        {{ ref('orders_semantic_view') }}
        metrics total_amount
    )
),
from_base as (
    select sum(amount) as total
    from {{ ref('orders_base') }}
)
select
    from_semantic_view.total as sv_total,
    from_base.total as base_total
from from_semantic_view
cross join from_base
where from_semantic_view.total <> from_base.total
