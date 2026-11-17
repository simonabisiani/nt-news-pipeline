-- All sections seen in the feed, enriched from the curated seed.
-- Sections that appear in the feed but are missing from the seed are kept
-- and flagged, so new sections never silently disappear from reporting.

with observed as (

    select distinct section_key, section, subsection
    from {{ ref('stg_nt__feed_items') }}
    where section_key is not null

),

curated as (

    select
        section || '/' || subsection as section_key,
        section_label,
        content_type,
        municipality_code
    from {{ ref('sections') }}

)

select
    observed.section_key,
    observed.section,
    observed.subsection,
    coalesce(curated.section_label, observed.section_key) as section_label,
    coalesce(curated.content_type, 'unmapped')            as content_type,
    curated.municipality_code,
    municipalities.municipality_name,
    curated.section_key is not null                       as is_mapped
from observed
left join curated using (section_key)
left join {{ ref('ostergotland_municipalities') }} as municipalities
    on curated.municipality_code = municipalities.municipality_code
