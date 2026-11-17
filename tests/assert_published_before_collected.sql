-- An article cannot be collected before it was published.
-- Allow 5 minutes for clock differences between NT's servers and ours.
select article_id, published_at, first_seen_at
from {{ ref('fct_articles') }}
where published_at > {{ dbt.dateadd('minute', 5, 'first_seen_at') }}
