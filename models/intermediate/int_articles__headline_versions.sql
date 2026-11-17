-- Every distinct headline an article has had, with when it was first and last seen.
-- Built from the raw log, so it captures edits even between snapshot runs.

with observations as (

    select article_id, headline, fetched_at
    from {{ ref('stg_nt__feed_items') }}

),

versions as (

    select
        article_id,
        headline,
        min(fetched_at) as first_seen_at,
        max(fetched_at) as last_seen_at,
        count(*)        as times_seen
    from observations
    group by article_id, headline

)

select
    {{ dbt.hash("article_id || '|' || headline") }} as headline_version_id,
    article_id,
    row_number() over (partition by article_id order by first_seen_at) as version_number,
    headline,
    first_seen_at,
    last_seen_at,
    times_seen
from versions
