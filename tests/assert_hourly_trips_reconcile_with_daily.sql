{#
    The hourly mart must add up to the daily mart, day by day.
    Returns every day where the two disagree.
#}

with hourly as (

    select
        date_day,
        sum(trips) as hourly_trips
    from {{ ref('fct_hourly_trips_weather') }}
    group by date_day

),

daily as (

    select
        date_day,
        trips as daily_trips
    from {{ ref('fct_daily_trips_weather') }}

)

select
    coalesce(daily.date_day, hourly.date_day) as date_day,
    daily.daily_trips,
    hourly.hourly_trips
from daily
full outer join hourly
    on daily.date_day = hourly.date_day
where
    daily.date_day is null
    or hourly.date_day is null
    or daily.daily_trips != hourly.hourly_trips
