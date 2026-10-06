{#
    Citibike trips per local hour, by user type. Covers every hour with at
    least one trip; the hourly mart adds the hours with none.
#}

select
    trip_hour,
    count(*) as trips,
    count_if(user_type = 'Subscriber') as subscriber_trips,
    count_if(user_type = 'Customer') as customer_trips,
    count_if(user_type = 'Unknown') as unknown_user_trips

from {{ ref('stg_citibike__trips') }}
group by trip_hour
