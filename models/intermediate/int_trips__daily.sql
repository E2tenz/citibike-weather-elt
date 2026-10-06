{#
    Citibike trips per local day, by user type, with the median trip length.
    Covers every day with at least one trip; days with none (the snowstorm
    closures) are added by the daily mart, which starts from a calendar.

    The median leaves out trips over 24 hours, which usually mean a bike
    was not docked properly.
#}

select
    trip_date,
    count(*) as trips,
    count_if(user_type = 'Subscriber') as subscriber_trips,
    count_if(user_type = 'Customer') as customer_trips,
    count_if(user_type = 'Unknown') as unknown_user_trips,
    round(median(iff(is_over_24_hours, null, trip_duration_sec)) / 60, 1) as median_trip_minutes

from {{ ref('stg_citibike__trips') }}
group by trip_date
