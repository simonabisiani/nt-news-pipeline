-- Articles published per day and section, in local (Swedish) time.

select
    cast(published_at_local as date)       as publish_date,
    section_label,
    content_type,
    municipality_name,
    count(*)                               as articles,
    sum(case when headline_was_changed then 1 else 0 end) as articles_with_changed_headline
from {{ ref('fct_articles') }}
where published_at is not null
group by 1, 2, 3, 4
