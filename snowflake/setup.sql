-- =============================================================================
-- One-time Snowflake setup: warehouse, database, schemas, roles, users, cost guard
-- Run in a Snowsight worksheet as ACCOUNTADMIN (trial accounts have this role).
-- =============================================================================

-- ---------------------------------------------------------------------------
-- 1. Compute: the smallest warehouse, suspended after 60 s idle to save credits
-- ---------------------------------------------------------------------------
use role sysadmin;

create warehouse if not exists NEWS_WH
    warehouse_size = 'XSMALL'
    auto_suspend = 60
    auto_resume = true
    initially_suspended = true
    comment = 'Compute for the NT news pipeline';

-- ---------------------------------------------------------------------------
-- 2. Storage: one database, one schema per layer
-- ---------------------------------------------------------------------------
create database if not exists NEWS;
create schema if not exists NEWS.RAW;           -- append-only loader output
create schema if not exists NEWS.STAGING;       -- dbt: cleaned, typed views
create schema if not exists NEWS.INTERMEDIATE;  -- dbt: joins, dedup, versions
create schema if not exists NEWS.MARTS;         -- dbt: business-facing tables
create schema if not exists NEWS.SNAPSHOTS;     -- dbt: change history (SCD2)

create table if not exists NEWS.RAW.NT_FEED_ITEMS (
    batch_id      varchar       not null,
    fetched_at    timestamp_ntz not null,
    feed_url      varchar       not null,
    item_position integer,
    guid          varchar,
    link          varchar,
    title         varchar,
    description   varchar,
    pub_date_raw  varchar
);

-- ---------------------------------------------------------------------------
-- 3. Access: least privilege, one role per responsibility
--    LOADER      -> may only insert into RAW
--    TRANSFORMER -> reads RAW, builds everything downstream (used by dbt)
--    REPORTER    -> reads MARTS only (BI tools, analysts)
-- ---------------------------------------------------------------------------
use role securityadmin;

create role if not exists LOADER;
create role if not exists TRANSFORMER;
create role if not exists REPORTER;

grant role LOADER to role sysadmin;
grant role TRANSFORMER to role sysadmin;
grant role REPORTER to role sysadmin;

-- LOADER
grant usage on warehouse NEWS_WH to role LOADER;
grant usage on database NEWS to role LOADER;
grant usage on schema NEWS.RAW to role LOADER;
grant select, insert on table NEWS.RAW.NT_FEED_ITEMS to role LOADER;

-- TRANSFORMER
grant usage on warehouse NEWS_WH to role TRANSFORMER;
grant usage on database NEWS to role TRANSFORMER;
grant usage on schema NEWS.RAW to role TRANSFORMER;
grant select on all tables in schema NEWS.RAW to role TRANSFORMER;
grant select on future tables in schema NEWS.RAW to role TRANSFORMER;
grant all privileges on schema NEWS.STAGING to role TRANSFORMER;
grant all privileges on schema NEWS.INTERMEDIATE to role TRANSFORMER;
grant all privileges on schema NEWS.MARTS to role TRANSFORMER;
grant all privileges on schema NEWS.SNAPSHOTS to role TRANSFORMER;

-- REPORTER
grant usage on warehouse NEWS_WH to role REPORTER;
grant usage on database NEWS to role REPORTER;
grant usage on schema NEWS.MARTS to role REPORTER;
grant select on future tables in schema NEWS.MARTS to role REPORTER;
grant select on future views in schema NEWS.MARTS to role REPORTER;

-- ---------------------------------------------------------------------------
-- 4. Service users with key-pair authentication (no passwords)
--    Generate keys locally, see README, then paste the public key below.
--    Sessions run in UTC so stored timestamps and freshness checks line up.
-- ---------------------------------------------------------------------------
use role useradmin;

create user if not exists SVC_LOADER
    type = service
    default_role = LOADER
    default_warehouse = NEWS_WH
    timezone = 'UTC'
    rsa_public_key = '<paste loader public key without header/footer>';

create user if not exists SVC_DBT
    type = service
    default_role = TRANSFORMER
    default_warehouse = NEWS_WH
    timezone = 'UTC'
    rsa_public_key = '<paste dbt public key without header/footer>';

use role securityadmin;
grant role LOADER to user SVC_LOADER;
grant role TRANSFORMER to user SVC_DBT;

-- ---------------------------------------------------------------------------
-- 5. Cost guard: notify at 80 %, suspend the warehouse at 100 % of the quota
-- ---------------------------------------------------------------------------
use role accountadmin;

create resource monitor if not exists NEWS_MONITOR
    with credit_quota = 10
    frequency = monthly
    start_timestamp = immediately
    triggers
        on 80 percent do notify
        on 100 percent do suspend;

alter warehouse NEWS_WH set resource_monitor = NEWS_MONITOR;
