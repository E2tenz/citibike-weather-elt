{#
    One row per local hour in the analysis window: trips by user type and
    the weather in that hour.

    - Starts from a full list of hours, so hours with no trips still appear.
    - hour_weather is "No reading" when the weather feed has nothing for
      that hour (about one hour in five). Those hours are not guessed.
    - Clock changes: the hour skipped each March (02:00) appears with no
      trips and no weather, and the hour repeated each November is counted
      once. Both sources use New York local time, so they stay aligned.
#}

with hours as (

    {{ dbt_utils.date_spine(
        datepart="hour",
        start_date="cast('" ~ var('analysis_start_date') ~ "' as timestamp_ntz)",
        end_date="dateadd(day, 1, cast('" ~ var('analysis_end_date') ~ "' as timestamp_ntz))"
    ) }}

),

dates as (

    select * from {{ ref('dim_date') }}

),

trips as (

    select * from {{ ref('int_trips__hourly') }}

),

weather as (

    select * from {{ ref('int_weather__hourly') }}

),

days_with_trips as (

    select trip_date from {{ ref('int_trips__daily') }}

)

select
    hours.date_hour as hour_start,
    dates.date_day,
    hour(hours.date_hour) as hour_of_day,
    dates.day_type,
    days_with_trips.trip_date is null as is_system_closed,

    coalesce(trips.trips, 0) as trips,
    coalesce(trips.subscriber_trips, 0) as subscriber_trips,
    coalesce(trips.customer_trips, 0) as customer_trips,
    coalesce(trips.unknown_user_trips, 0) as unknown_user_trips,

    weather.weather_hour is not null as has_weather_reading,
    case
        when weather.weather_hour is null then 'No reading'
        when weather.is_snow then 'Snow'
        when weather.is_rain then 'Rain'
        else 'Dry'
    end as hour_weather,
    case
        when weather.weather_hour is null then 4
        when weather.is_snow then 3
        when weather.is_rain then 2
        else 1
    end as hour_weather_sort,
    round(weather.avg_temp_c, 1) as temp_c,
    weather.max_rain_1h_mm as rain_1h_mm

from hours
inner join dates
    on hours.date_hour::date = dates.date_day
left join trips
    on hours.date_hour = trips.trip_hour
left join weather
    on hours.date_hour = weather.weather_hour
left join days_with_trips
    on dates.date_day = days_with_trips.trip_date
