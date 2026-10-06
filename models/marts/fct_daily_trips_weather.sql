{#
    One row per day in the analysis window: trips by user type, the day's
    weather, and how the day compares with a typical dry day.

    - Starts from the calendar, so the snowstorm closures appear with zero
      trips instead of disappearing (decision 18).
    - weather_category comes from rain and snow during riding hours
      (decisions 26 and 30). Days with too few weather readings are
      labelled "Not enough weather data" instead of guessed (decision 27).
    - dry_day_baseline_trips is the median trips of dry, open days in the
      same month of the same year with the same day type. pct_vs_dry_day
      compares each day with it, which takes season, growth and the
      weekday pattern out of the comparison (decisions 17 and 28).
      Subscribers and customers get their own baselines, because members
      and casual riders may react to weather differently.
#}

with dates as (

    select * from {{ ref('dim_date') }}

),

trips as (

    select * from {{ ref('int_trips__daily') }}

),

weather as (

    select * from {{ ref('int_weather__daily') }}

),

joined as (

    select
        dates.date_day,
        dates.calendar_year,
        dates.month_number,
        dates.day_type,

        trips.trip_date is null as is_system_closed,
        coalesce(trips.trips, 0) as trips,
        coalesce(trips.subscriber_trips, 0) as subscriber_trips,
        coalesce(trips.customer_trips, 0) as customer_trips,
        coalesce(trips.unknown_user_trips, 0) as unknown_user_trips,
        trips.median_trip_minutes,

        coalesce(weather.hours_with_weather, 0) as hours_with_weather,
        coalesce(weather.daytime_hours_with_weather, 0) as daytime_hours_with_weather,
        coalesce(weather.daytime_hours_with_weather, 0)
        >= {{ var('min_daytime_weather_hours') }} as has_enough_weather_data,
        round(weather.avg_temp_c, 1) as avg_temp_c,
        round(weather.min_temp_c, 1) as min_temp_c,
        round(weather.max_temp_c, 1) as max_temp_c,
        round(weather.avg_humidity_pct, 0) as avg_humidity_pct,
        round(weather.avg_wind_speed_ms, 1) as avg_wind_speed_ms,
        round(weather.max_wind_gust_ms, 1) as max_wind_gust_ms,
        coalesce(weather.daytime_rain_hours, 0) as daytime_rain_hours,
        coalesce(weather.daytime_snow_hours, 0) as daytime_snow_hours

    from dates
    left join trips
        on dates.date_day = trips.trip_date
    left join weather
        on dates.date_day = weather.weather_date

),

categorised as (

    select
        *,
        case
            when not has_enough_weather_data then 'Not enough weather data'
            when daytime_snow_hours > 0 then 'Snow'
            when daytime_rain_hours >= 3 then 'Rain'
            when daytime_rain_hours > 0 then 'Light rain'
            else 'Dry'
        end as weather_category,
        case
            when not has_enough_weather_data then 5
            when daytime_snow_hours > 0 then 4
            when daytime_rain_hours >= 3 then 3
            when daytime_rain_hours > 0 then 2
            else 1
        end as weather_category_sort,
        case
            when avg_temp_c < 0 then 'Below 0 C'
            when avg_temp_c < 10 then '0 to 10 C'
            when avg_temp_c < 20 then '10 to 20 C'
            when avg_temp_c < 25 then '20 to 25 C'
            when avg_temp_c >= 25 then '25 C and above'
        end as temperature_band,
        case
            when avg_temp_c < 0 then 1
            when avg_temp_c < 10 then 2
            when avg_temp_c < 20 then 3
            when avg_temp_c < 25 then 4
            when avg_temp_c >= 25 then 5
        end as temperature_band_sort

    from joined

),

with_baseline as (

    select
        *,
        median(
            case when weather_category = 'Dry' and not is_system_closed then trips end
        ) over (
            partition by calendar_year, month_number, day_type
        ) as dry_day_baseline_trips,
        median(
            case when weather_category = 'Dry' and not is_system_closed then subscriber_trips end
        ) over (
            partition by calendar_year, month_number, day_type
        ) as dry_day_baseline_subscriber_trips,
        median(
            case when weather_category = 'Dry' and not is_system_closed then customer_trips end
        ) over (
            partition by calendar_year, month_number, day_type
        ) as dry_day_baseline_customer_trips

    from categorised

)

select
    date_day,
    day_type,
    is_system_closed,
    trips,
    subscriber_trips,
    customer_trips,
    unknown_user_trips,
    median_trip_minutes,
    weather_category,
    weather_category_sort,
    temperature_band,
    temperature_band_sort,
    avg_temp_c,
    min_temp_c,
    max_temp_c,
    avg_humidity_pct,
    avg_wind_speed_ms,
    max_wind_gust_ms,
    daytime_rain_hours,
    daytime_snow_hours,
    hours_with_weather,
    daytime_hours_with_weather,
    has_enough_weather_data,
    dry_day_baseline_trips,
    case
        when not is_system_closed and dry_day_baseline_trips > 0
            then round(trips / dry_day_baseline_trips - 1, 3)
    end as pct_vs_dry_day,
    dry_day_baseline_subscriber_trips,
    case
        when not is_system_closed and dry_day_baseline_subscriber_trips > 0
            then round(subscriber_trips / dry_day_baseline_subscriber_trips - 1, 3)
    end as subscriber_pct_vs_dry_day,
    dry_day_baseline_customer_trips,
    case
        when not is_system_closed and dry_day_baseline_customer_trips > 0
            then round(customer_trips / dry_day_baseline_customer_trips - 1, 3)
    end as customer_pct_vs_dry_day

from with_baseline
