-- One row per article: its most recent state plus collection metadata.

with observations as (

    select * from {{ ref('stg_nt__feed_items') }}

),

latest as (

    select *
    from observations
    qualify row_number() over (partition by article_id order by fetched_at desc) = 1

),

history as (

    select
        article_id,
        min(fetched_at)          as first_seen_at,
        max(fetched_at)          as last_seen_at,
        count(distinct batch_id) as times_seen,
        count(distinct headline) as headline_versions
    from observations
    group by article_id

),

first_headline as (

    select article_id, headline as first_headline
    from {{ ref('int_articles__headline_versions') }}
    where version_number = 1

)

select
    latest.article_id,
    latest.article_url,
    latest.url_slug,
    latest.section_key,
    latest.headline,
    first_headline.first_headline,
    latest.lede_text,
    latest.published_at,
    history.first_seen_at,
    history.last_seen_at,
    history.times_seen,
    history.headline_versions
from latest
inner join history using (article_id)
left join first_headline using (article_id)
