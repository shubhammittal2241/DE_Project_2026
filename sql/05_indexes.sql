SET search_path TO mmt;
CREATE EXTENSION IF NOT EXISTS pg_trgm;

CREATE INDEX IF NOT EXISTS idx_flights_route_date_fare
    ON flights (origin, destination, departure_at, base_fare);

CREATE INDEX IF NOT EXISTS idx_flights_search
    ON flights (origin, destination, departure_at)
    INCLUDE (flight_no, arrival_at, base_fare, total_seats)
    WHERE status <> 'CANCELLED';

CREATE INDEX IF NOT EXISTS idx_flight_bookings_flight_id
    ON flight_bookings (flight_id)
    INCLUDE (booking_id, passengers);

CREATE INDEX IF NOT EXISTS idx_flights_delayed
    ON flights (departure_at)
    INCLUDE (flight_no, origin, destination)
    WHERE status = 'DELAYED';

CREATE INDEX IF NOT EXISTS idx_flights_w04
    ON flights (departure_at)
    WHERE status IN ('SCHEDULED', 'DELAYED');

CREATE INDEX IF NOT EXISTS idx_hotels_search
    ON hotels (city_name, star_rating, ((amenities ->> 'pool')), user_rating DESC NULLS LAST)
    INCLUDE (hotel_name);

CREATE INDEX IF NOT EXISTS idx_room_types_hotel
    ON room_types (hotel_id, price_per_night)
    INCLUDE (room_name, total_rooms);

CREATE INDEX IF NOT EXISTS idx_hotel_bookings_rt_dates
    ON hotel_bookings (room_type_id, check_in, check_out)
    INCLUDE (rooms, booking_id);

CREATE INDEX IF NOT EXISTS idx_hotel_bookings_dates
    ON hotel_bookings (check_in, check_out)
    INCLUDE (hotel_id, booking_id, rooms);

CREATE INDEX IF NOT EXISTS idx_hotel_bookings_w05
    ON hotel_bookings (check_in)
    WHERE room_number IS NULL;

CREATE INDEX IF NOT EXISTS idx_hotels_city
    ON hotels (city_name, hotel_id)
    INCLUDE (hotel_name);