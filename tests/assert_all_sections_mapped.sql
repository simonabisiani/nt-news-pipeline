-- Warns when the feed contains a section that is not in seeds/sections.csv.
-- Fix: add the new section to the seed and run dbt seed.
{{ config(severity = 'warn') }}

select section_key
from {{ ref('dim_section') }}
where not is_mapped
