-- Full headline history for articles whose headline was edited after publication.

select
    versions.article_id,
    articles.article_url,
    articles.section_label,
    versions.version_number,
    versions.headline,
    versions.first_seen_at,
    versions.last_seen_at
from {{ ref('int_articles__headline_versions') }} as versions
inner join {{ ref('fct_articles') }} as articles
    on versions.article_id = articles.article_id
where articles.headline_was_changed
