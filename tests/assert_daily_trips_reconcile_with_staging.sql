{#
    Every trip in the analysis window must be counted exactly once in the
    daily mart: none lost and none doubled by the joins to the calendar and
    the weather. Returns a row only if the totals differ.
#}

with mart as (

    select sum(trips) as mart_trips
    from {{ ref('fct_daily_trips_weather') }}

),

staging as (

    select count(*) as staging_trips
    from {{ ref('stg_citibike__trips') }}
    where
        trip_date between '{{ var("analysis_start_date") }}'
        and '{{ var("analysis_end_date") }}'

)

select
    mart.mart_trips,
    staging.staging_trips
from mart
cross join staging
where mart.mart_trips != staging.staging_trips
