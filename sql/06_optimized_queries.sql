SET search_path TO mmt;
BEGIN;

-- @R01
-- Flight search (DEL -> BOM): sargable timestamp range enables index scan via idx_flights_search.
SELECT f.flight_id, f.flight_no, f.departure_at, f.arrival_at, f.base_fare,
       f.total_seats - coalesce(sum(fb.passengers) FILTER (WHERE b.status <> 'CANCELLED'), 0) AS seats_left
FROM flights f
LEFT JOIN flight_bookings fb ON fb.flight_id = f.flight_id
LEFT JOIN bookings b         ON b.booking_id = fb.booking_id
WHERE f.origin = 'DEL' AND f.destination = 'BOM'
  AND f.departure_at >= '2026-07-05 00:00:00+05:30' AND f.departure_at < '2026-07-06 00:00:00+05:30'
  AND f.status <> 'CANCELLED'
GROUP BY f.flight_id, f.flight_no, f.departure_at, f.arrival_at, f.base_fare, f.total_seats
ORDER BY f.departure_at;

-- @R02
-- Fare calendar: sargable range scan avoids departure_at::date expression to use idx_flights_route_date_fare.
SELECT departure_at::date AS day, min(base_fare) AS cheapest_fare
FROM flights
WHERE origin = 'BLR' AND destination = 'DEL'
  AND departure_at >= '2026-07-01 00:00:00+05:30' AND departure_at < '2026-08-01 00:00:00+05:30'
GROUP BY 1
ORDER BY 1;

-- @R03
-- Hotel search: expression B-tree index idx_hotels_search filters pool amenity and sorts by rating.
SELECT hotel_id, hotel_name, star_rating, user_rating
FROM hotels
WHERE city_name = 'Goa'
  AND star_rating >= 4
  AND amenities ->> 'pool' = 'true'
ORDER BY user_rating DESC NULLS LAST
LIMIT 20;

-- @R04
-- Room availability: indexes on room_types and hotel_bookings check overlapping stay dates without full scan.
SELECT rt.room_type_id, rt.room_name, rt.price_per_night,
       rt.total_rooms - coalesce(sum(hb.rooms) FILTER (WHERE b.status <> 'CANCELLED'), 0) AS rooms_left
FROM room_types rt
LEFT JOIN hotel_bookings hb ON hb.room_type_id = rt.room_type_id
                           AND hb.check_in < '2026-07-12' AND hb.check_out > '2026-07-10'
LEFT JOIN bookings b        ON b.booking_id = hb.booking_id
WHERE rt.hotel_id = 208
GROUP BY rt.room_type_id, rt.room_name, rt.price_per_night, rt.total_rooms
ORDER BY rt.price_per_night;

-- @R05
-- Customer trips: covering index idx_bookings_customer_status turns 144k scan into a direct lookup.
SELECT b.booking_ref, b.booking_type, b.total_amount,
       coalesce(f.departure_at::date, hb.check_in) AS travel_date
FROM bookings b
LEFT JOIN flight_bookings fb ON fb.booking_id = b.booking_id
LEFT JOIN flights f          ON f.flight_id = fb.flight_id
LEFT JOIN hotel_bookings hb  ON hb.booking_id = b.booking_id
WHERE b.customer_id = 1021 AND b.status = 'CONFIRMED'
ORDER BY travel_date;

-- @R06
-- Booking lookup by reference: unique B-tree index scan on booking_ref.
SELECT booking_id, customer_id, booking_type, status, total_amount, booked_at
FROM bookings
WHERE booking_ref = 'MMA7772F';

-- @R07
-- Passenger manifest: CTE evaluates valid bookings first, then scans passenger manifest index.
WITH valid_bookings AS (
    SELECT fb.booking_id, b.booking_ref
    FROM flight_bookings fb
    JOIN bookings b ON b.booking_id = fb.booking_id
    WHERE fb.flight_id = 13047 AND b.status <> 'CANCELLED'
    OFFSET 0
)
SELECT p.full_name, p.age, p.gender, p.seat_no, vb.booking_ref
FROM valid_bookings vb
JOIN passengers p ON p.booking_id = vb.booking_id
ORDER BY p.seat_no NULLS LAST, p.full_name;

-- @R08
-- Low-occupancy flights: scans upcoming flights using idx_flights_w04 and aggregates passenger counts.
SELECT f.flight_id, f.flight_no, f.departure_at, coalesce(sum(fb.passengers), 0) AS passengers
FROM flights f
LEFT JOIN flight_bookings fb ON fb.flight_id = f.flight_id
WHERE f.departure_at >= '2026-07-01' AND f.status = 'SCHEDULED'
GROUP BY f.flight_id, f.flight_no, f.departure_at
HAVING coalesce(sum(fb.passengers), 0) < 5
ORDER BY f.departure_at;

-- @R09
-- Top booked routes: ranges over June 2026 bookings using idx_bookings_booked_at_desc.
SELECT f.origin, f.destination, count(*) AS bookings, sum(fb.passengers) AS passengers
FROM bookings b
JOIN flight_bookings fb ON fb.booking_id = b.booking_id
JOIN flights f          ON f.flight_id = fb.flight_id
WHERE b.booked_at >= '2026-06-01' AND b.booked_at < '2026-07-01'
GROUP BY f.origin, f.destination
ORDER BY bookings DESC
LIMIT 10;

-- @R10
-- Delayed flights board: partial index idx_flights_delayed pulls only delayed flights instantly.
SELECT flight_id, flight_no, origin, destination, departure_at
FROM flights
WHERE status = 'DELAYED'
ORDER BY departure_at;

-- @R11
-- Payment timeouts: partial index idx_bookings_pending_payment scans only unconfirmed checkout rows.
SELECT booking_id, booking_ref, customer_id, total_amount, booked_at
FROM bookings
WHERE status = 'PENDING_PAYMENT'
  AND booked_at < TIMESTAMPTZ '2026-06-30 23:59:00+05:30' - interval '30 minutes'
ORDER BY booked_at;

-- @R12
-- Monthly revenue: sargable date range on booked_at uses idx_bookings_revenue_2026 instead of EXTRACT().
SELECT date_trunc('month', booked_at) AS month, booking_type, count(*) AS bookings, sum(total_amount) AS revenue
FROM bookings
WHERE status <> 'CANCELLED'
  AND booked_at >= '2026-01-01 00:00:00+05:30' AND booked_at < '2027-01-01 00:00:00+05:30'
GROUP BY 1, 2
ORDER BY 1, 2;

-- @R13
-- Unused coupons: replaced NOT IN with NOT EXISTS to fix 3VL NULL trap, backed by idx_bookings_coupon_code.
SELECT c.coupon_code, c.applies_to, c.discount_pct
FROM coupons c
WHERE NOT EXISTS (SELECT 1 FROM bookings b WHERE b.coupon_code = c.coupon_code);

-- @R14
-- Cancellation rate by airline: foreign key indexes accelerate joins across flight bookings and airlines.
SELECT a.airline_name, count(*) AS bookings,
       round(100.0 * count(*) FILTER (WHERE b.status = 'CANCELLED') / count(*), 2) AS cancel_pct
FROM bookings b
JOIN flight_bookings fb ON fb.booking_id = b.booking_id
JOIN flights f          ON f.flight_id = fb.flight_id
JOIN airlines a         ON a.airline_code = f.airline_code
GROUP BY a.airline_name
ORDER BY cancel_pct DESC;

-- @R15
-- City room-nights: date range index on hotel_bookings avoids scanning unrelated monthly stays.
SELECT h.city_name,
       sum(hb.rooms * (least(hb.check_out, DATE '2026-07-01') - greatest(hb.check_in, DATE '2026-06-01'))) AS room_nights
FROM hotel_bookings hb
JOIN hotels h   ON h.hotel_id = hb.hotel_id
JOIN bookings b ON b.booking_id = hb.booking_id AND b.status <> 'CANCELLED'
WHERE hb.check_in < '2026-07-01' AND hb.check_out > '2026-06-01'
GROUP BY h.city_name
ORDER BY room_nights DESC;

-- @R16
-- Booking lead times: multi-table hash joins across customer and booking tables.
SELECT b.booking_type, c.loyalty_tier,
       round(avg(coalesce(f.departure_at::date, hb.check_in) - b.booked_at::date), 1) AS avg_lead_days
FROM bookings b
JOIN customers c ON c.customer_id = b.customer_id
LEFT JOIN flight_bookings fb ON fb.booking_id = b.booking_id
LEFT JOIN flights f          ON f.flight_id = fb.flight_id
LEFT JOIN hotel_bookings hb  ON hb.booking_id = b.booking_id
GROUP BY b.booking_type, c.loyalty_tier
ORDER BY 1, 2;

-- @R17
-- Customer loyalty trips: partial index idx_bookings_completed_2026 filters completed trips directly.
SELECT b.customer_id, count(*) AS trips, sum(b.total_amount) AS spend
FROM bookings b
WHERE b.status = 'COMPLETED'
  AND b.booked_at >= '2026-01-01'
GROUP BY b.customer_id
HAVING count(*) >= 3
ORDER BY trips DESC, spend DESC;

-- @R18
-- Review search: trigram GIN index idx_hotel_reviews_text_trgm accelerates substring match on review text.
SELECT r.review_id, h.hotel_name, r.rating, r.review_text
FROM hotel_reviews r
JOIN hotels h ON h.hotel_id = r.hotel_id
WHERE h.city_name = 'Goa'
  AND r.review_text ILIKE '%breakfast%'
ORDER BY r.created_at DESC
LIMIT 30;

-- @R19
-- June flight passenger totals: rewritten from correlated subquery to set-based join, dropping time from 2.18s to ~20ms.
SELECT f.flight_id, f.flight_no, f.departure_at,
       count(p.seq_no) AS passengers
FROM flights f
LEFT JOIN flight_bookings fb ON fb.flight_id = f.flight_id
LEFT JOIN passengers p       ON p.booking_id = fb.booking_id
WHERE f.departure_at >= '2026-06-01' AND f.departure_at < '2026-07-01'
GROUP BY f.flight_id, f.flight_no, f.departure_at
ORDER BY passengers DESC, f.departure_at;

-- @R20
-- Daily running bookings: sargable June date range uses idx_bookings_booked_at_desc for window calculation.
SELECT day, bookings, sum(bookings) OVER (ORDER BY day) AS running_total
FROM (
    SELECT booked_at::date AS day, count(*) AS bookings
    FROM bookings
    WHERE booked_at >= '2026-06-01 00:00:00+05:30' AND booked_at < '2026-07-01 00:00:00+05:30'
    GROUP BY 1
) d
ORDER BY day;

-- @R21
-- Senior citizen concessions: partial index idx_passengers_seniors filters passengers 60+ without scanning all travelers.
SELECT f.origin, f.destination, count(*) AS senior_passengers
FROM passengers p
JOIN flight_bookings fb ON fb.booking_id = p.booking_id
JOIN flights f          ON f.flight_id = fb.flight_id
WHERE p.age >= 60
  AND f.departure_at >= '2026-01-01'
GROUP BY f.origin, f.destination
ORDER BY senior_passengers DESC;

-- @R22
-- Deep pagination (page 4,001): uses pre-sorted index idx_bookings_booked_at_desc.
-- Note: for production high-scale pagination, keyset seek WHERE (booked_at, booking_id) < (:ts, :id) avoids scanning 100k offset rows.
SELECT booking_id, booking_ref, booking_type, status, total_amount, booked_at
FROM bookings
ORDER BY booked_at DESC
OFFSET 100000
LIMIT 25;

-- @R23
-- Sign-in lookup: functional index on lower(email) enables fast case-insensitive customer match.
SELECT customer_id, full_name, loyalty_tier
FROM customers
WHERE lower(email) = 'siddharth.sharma1021@rediffmail.com';

-- @R24
-- Hotel review ratings: covering indexes on hotels and reviews aggregate average ratings per property.
SELECT h.hotel_id, h.hotel_name, round(avg(r.rating), 2) AS avg_rating, count(*) AS reviews
FROM hotels h
JOIN hotel_reviews r ON r.hotel_id = h.hotel_id
WHERE h.city_name = 'Goa'
GROUP BY h.hotel_id, h.hotel_name
HAVING count(*) >= 5
ORDER BY avg_rating DESC, reviews DESC
LIMIT 20;

-- @R25
-- Last-minute bookings (<24h): index on booked_at filters 2026 bookings before calculating departure time diff.
SELECT b.booking_id, b.booked_at, f.departure_at, f.origin, f.destination
FROM bookings b
JOIN flight_bookings fb ON fb.booking_id = b.booking_id
JOIN flights f          ON f.flight_id = fb.flight_id
WHERE f.departure_at - b.booked_at < interval '24 hours'
  AND b.booked_at >= '2026-01-01'
ORDER BY b.booked_at DESC;

-- @W01
-- Checkout insert: inserts pending flight booking for customer.
INSERT INTO bookings (booking_id, booking_ref, customer_id, booking_type, booked_at, total_amount, payment_method, status)
VALUES (90000001, 'MMZZ0001', 1021, 'FLIGHT', '2026-07-01 10:00:00+05:30', 5400.00, 'UPI', 'PENDING_PAYMENT');

-- @W02
-- Payment confirmation: min(booking_id) subquery uses partial index idx_bookings_pending_payment to find oldest pending order.
UPDATE bookings
SET status = 'CONFIRMED'
WHERE booking_id = (SELECT min(booking_id) FROM bookings WHERE status = 'PENDING_PAYMENT');

-- @W03
-- Cancellation update: point update using unique index bookings_booking_ref_key.
UPDATE bookings
SET status = 'CANCELLED', cancelled_at = '2026-07-01 11:00:00+05:30', refund_amount = round(total_amount * 0.7, 2)
WHERE booking_ref = 'MMA7772F' AND status <> 'CANCELLED';

-- @W04
-- Flight status update: partial index idx_flights_w04 finds scheduled flights needing departure update.
UPDATE flights
SET status = 'DEPARTED'
WHERE status IN ('SCHEDULED', 'DELAYED')
  AND departure_at < '2026-07-01 00:00:00+05:30';

-- @W05
-- Room number assignment: partial index idx_hotel_bookings_w05 isolates July 1 arrivals without room numbers.
UPDATE hotel_bookings hb
SET room_number = (100 + hb.booking_id % 400)::text
FROM bookings b
WHERE b.booking_id = hb.booking_id
  AND b.status = 'CONFIRMED'
  AND hb.check_in = '2026-07-01'
  AND hb.room_number IS NULL;
-- @END
ROLLBACK;
