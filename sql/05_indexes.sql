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