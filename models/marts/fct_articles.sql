{{
    config(
        materialized = 'incremental',
        unique_key = 'article_id',
        on_schema_change = 'append_new_columns'
    )
}}

-- One row per article. Incremental: each run only reprocesses articles that
-- were seen again since the last run, then upserts them on article_id.

with articles as (

    select * from {{ ref('int_articles__latest') }}

    {% if is_incremental() %}
    where last_seen_at > (select max(last_seen_at) from {{ this }})
    {% endif %}

)

select
    articles.article_id,
    articles.article_url,
    articles.headline,
    articles.first_headline,
    articles.lede_text,
    articles.section_key,
    sections.section_label,
    sections.content_type,
    sections.municipality_code,
    sections.municipality_name,
    articles.published_at,
    {{ to_reporting_tz('articles.published_at') }}       as published_at_local,
    articles.first_seen_at,
    articles.last_seen_at,
    {{ dbt.datediff('articles.published_at', 'articles.first_seen_at', 'minute') }}
                                                         as minutes_until_collected,
    articles.times_seen,
    articles.headline_versions,
    articles.headline_versions > 1                       as headline_was_changed
from articles
left join {{ ref('dim_section') }} as sections using (section_key)
