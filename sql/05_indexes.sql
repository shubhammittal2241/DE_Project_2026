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

CREATE INDEX IF NOT EXISTS idx_bookings_customer_status
    ON bookings (customer_id, status)
    INCLUDE (booking_ref, booking_type, total_amount);

CREATE INDEX IF NOT EXISTS idx_bookings_pending_payment
    ON bookings (booking_id, booked_at)
    WHERE status = 'PENDING_PAYMENT';

CREATE INDEX IF NOT EXISTS idx_bookings_revenue_2026
    ON bookings (booked_at, booking_type)
    INCLUDE (total_amount)
    WHERE status <> 'CANCELLED';

CREATE INDEX IF NOT EXISTS idx_bookings_coupon_code
    ON bookings (coupon_code)
    WHERE coupon_code IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_bookings_completed_2026
    ON bookings (customer_id, total_amount)
    WHERE status = 'COMPLETED' AND booked_at >= '2026-01-01';

CREATE INDEX IF NOT EXISTS idx_bookings_booked_at_desc
    ON bookings (booked_at DESC, booking_id DESC)
    INCLUDE (booking_ref, booking_type, status, total_amount);

CREATE INDEX IF NOT EXISTS idx_bookings_id_ref_status
    ON bookings (booking_id)
    INCLUDE (booking_ref, status);

CREATE INDEX IF NOT EXISTS idx_hotel_reviews_text_trgm
    ON hotel_reviews USING gin (review_text gin_trgm_ops);

CREATE INDEX IF NOT EXISTS idx_hotel_reviews_hotel_rating
    ON hotel_reviews (hotel_id, rating);

CREATE INDEX IF NOT EXISTS idx_passengers_seniors
    ON passengers (booking_id)
    WHERE age >= 60;

CREATE INDEX IF NOT EXISTS idx_customers_lower_email
    ON customers (lower(email))
    INCLUDE (customer_id, full_name, loyalty_tier);

CREATE INDEX IF NOT EXISTS idx_passengers_manifest
    ON passengers (booking_id)
    INCLUDE (full_name, age, gender, seat_no);

ANALYZE;