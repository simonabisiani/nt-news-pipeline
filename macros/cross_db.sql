{#
  Small adapter-dispatched helpers so the same models run on Snowflake (prod)
  and DuckDB (local dev and CI).
#}

{# Parse an RFC 822 date ("Tue, 17 Nov 2026 10:54:41 +0100") to a UTC timestamp. #}
{% macro parse_rfc822_utc(column) %}
    {{ return(adapter.dispatch('parse_rfc822_utc')(column)) }}
{% endmacro %}

{% macro snowflake__parse_rfc822_utc(column) %}
    convert_timezone('UTC', try_to_timestamp_tz({{ column }}, 'DY, DD MON YYYY HH24:MI:SS TZHTZM'))::timestamp_ntz
{% endmacro %}

{% macro duckdb__parse_rfc822_utc(column) %}
    (try_strptime({{ column }}, '%a, %d %b %Y %H:%M:%S %z') at time zone 'UTC')
{% endmacro %}

{# Remove HTML tags and common entities from feed descriptions. #}
{% macro strip_html(column) %}
    {{ return(adapter.dispatch('strip_html')(column)) }}
{% endmacro %}

{% macro snowflake__strip_html(column) %}
    nullif(trim(replace(regexp_replace({{ column }}, '<[^>]+>', ' '), '&nbsp;', ' ')), '')
{% endmacro %}

{% macro duckdb__strip_html(column) %}
    nullif(trim(replace(regexp_replace({{ column }}, '<[^>]+>', ' ', 'g'), '&nbsp;', ' ')), '')
{% endmacro %}

{# Convert a UTC timestamp to the reporting timezone (local wall-clock time). #}
{% macro to_reporting_tz(column) %}
    {{ return(adapter.dispatch('to_reporting_tz')(column)) }}
{% endmacro %}

{% macro snowflake__to_reporting_tz(column) %}
    convert_timezone('UTC', '{{ var("reporting_timezone") }}', {{ column }})
{% endmacro %}

{% macro duckdb__to_reporting_tz(column) %}
    (({{ column }} at time zone 'UTC') at time zone '{{ var("reporting_timezone") }}')
{% endmacro %}
