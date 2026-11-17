-- Warns if two consecutive loader runs are more than 6 hours apart,
-- which means scheduled runs were missed and articles may be lost.
{{ config(severity = 'warn') }}

with runs as (

    select distinct batch_id, fetched_at
    from {{ ref('stg_nt__feed_items') }}

),

gaps as (

    select
        fetched_at,
        lag(fetched_at) over (order by fetched_at) as previous_fetched_at
    from runs

)

select *
from gaps
where {{ dbt.datediff('previous_fetched_at', 'fetched_at', 'hour') }} > 6
