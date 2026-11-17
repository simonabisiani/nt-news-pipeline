-- One row per article per fetch: typed, cleaned and parsed, but not aggregated.

with source as (

    select * from {{ source('raw', 'nt_feed_items') }}

),

renamed as (

    select
        batch_id,
        fetched_at,
        feed_url,
        item_position,
        trim(guid)                                as article_id,
        trim(link)                                as article_url,
        trim(title)                               as headline,
        {{ strip_html('description') }}           as lede_text,
        pub_date_raw,
        {{ parse_rfc822_utc('pub_date_raw') }}    as published_at,

        -- URL pattern: https://www.nt.se/<section>/<subsection>/artikel/<slug>/<id>
        nullif(split_part(link, '/', 4), '')      as section,
        nullif(split_part(link, '/', 5), '')      as subsection,
        nullif(split_part(link, '/', 7), '')      as url_slug

    from source
    where guid is not null

),

deduplicated as (

    -- A feed can occasionally list the same item twice in one response.
    select *
    from renamed
    qualify row_number() over (
        partition by batch_id, article_id
        order by item_position
    ) = 1

)

select
    {{ dbt.hash("batch_id || '|' || article_id") }} as feed_item_id,
    *,
    section || '/' || subsection                     as section_key
from deduplicated
