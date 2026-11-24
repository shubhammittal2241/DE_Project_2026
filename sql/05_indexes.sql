-- =====================================================================
-- MakeMyTrip DBMS Project: Supporting Secondary Indexes (Phase 4).
-- Every index includes a comment documenting which queries it serves
-- and why this specific index type and column order was selected.
-- =====================================================================

SET search_path TO mmt;
CREATE EXTENSION IF NOT EXISTS pg_trgm;

-- ---------------------------------------------------------------------
-- 1. FLIGHTS & FLIGHT BOOKINGS INDEXES
-- ---------------------------------------------------------------------

-- Serves: R02 (Fare Calendar: cheapest BLR -> DEL fare for each day of July 2026).
-- Why: Composite B-tree covering index. Equality route columns (origin, destination)
--      come first, followed by range filter (departure_at) and projected metric (base_fare)
--      to allow an Index Only Scan without visiting table heap pages.
CREATE INDEX IF NOT EXISTS idx_flights_route_date_fare
    ON flights (origin, destination, departure_at, base_fare);

-- Serves: R01 (Flight Search: DEL -> BOM on 5 July 2026 with seats left).
-- Why: Partial composite B-tree covering index. Filters out CANCELLED flights at the index level.
--      Leading equality route columns followed by departure_at range; INCLUDE clause supplies
--      flight_no, arrival_at, base_fare, and total_seats for Index Only Scan execution.
CREATE INDEX IF NOT EXISTS idx_flights_search
    ON flights (origin, destination, departure_at)
    INCLUDE (flight_no, arrival_at, base_fare, total_seats)
    WHERE status <> 'CANCELLED';

-- Serves: R01, R07, R08, R09, R14, R19, R21 (Flight passenger aggregation & joins).
-- Why: B-tree index on foreign key flight_id with INCLUDE (booking_id, passengers).
--      Converts full sequential scans of flight_bookings (85k+ rows) into fast index lookups
--      when joining flights to reservations, providing passenger counts directly from the leaf pages.
CREATE INDEX IF NOT EXISTS idx_flight_bookings_flight_id
    ON flight_bookings (flight_id)
    INCLUDE (booking_id, passengers);

-- Serves: R10 (Flight Status Board: delayed flights).
-- Why: Highly selective partial B-tree index on departure_at for rows WHERE status = 'DELAYED'.
--      Because delayed flights make up <0.1% of all records, this index is tiny (16 kB)
--      and yields instant sub-millisecond retrieval without scanning on-time flights.
CREATE INDEX IF NOT EXISTS idx_flights_delayed
    ON flights (departure_at)
    INCLUDE (flight_no, origin, destination)
    WHERE status = 'DELAYED';

-- Serves: W04 (Flight ops batch update) and R08 (Upcoming low-load flights).
-- Why: Partial B-tree index on departure_at for active flights (SCHEDULED or DELAYED).
--      Allows the batch departure update to locate target rows directly without table scans.
CREATE INDEX IF NOT EXISTS idx_flights_w04
    ON flights (departure_at)
    WHERE status IN ('SCHEDULED', 'DELAYED');

-- ---------------------------------------------------------------------
-- 2. HOTELS & ROOM AVAILABILITY INDEXES
-- ---------------------------------------------------------------------

-- Serves: R03 (Hotel search: 4★+ in Goa with swimming pool, best rated first).
-- Why: Multi-column expression B-tree index. Places city_name equality filter first,
--      star_rating range filter second, JSONB boolean extraction ((amenities ->> 'pool')) third,
--      and matches the ORDER BY user_rating DESC NULLS LAST to avoid an in-memory sort node.
CREATE INDEX IF NOT EXISTS idx_hotels_search
    ON hotels (city_name, star_rating, ((amenities ->> 'pool')), user_rating DESC NULLS LAST)
    INCLUDE (hotel_name);

-- Serves: R04 (Room availability per room type for hotel 208).
-- Why: Composite B-tree index on foreign key hotel_id followed by price_per_night sort order.
--      INCLUDE clause covers room_name and total_rooms to avoid fetching heap tuples.
CREATE INDEX IF NOT EXISTS idx_room_types_hotel
    ON room_types (hotel_id, price_per_night)
    INCLUDE (room_name, total_rooms);

-- Serves: R04 (Room availability date-range overlap check).
-- Why: Composite B-tree index on room_type_id and stay interval (check_in, check_out).
--      Enables range scans to calculate rooms already booked during a customer's requested stay.
CREATE INDEX IF NOT EXISTS idx_hotel_bookings_rt_dates
    ON hotel_bookings (room_type_id, check_in, check_out)
    INCLUDE (rooms, booking_id);

-- Serves: R15 (City room-nights sold for stays in June 2026).
-- Why: Composite B-tree index on stay dates (check_in, check_out) with covering hotel_id and rooms.
--      Accelerates date overlap calculations for monthly city partner settlements.
CREATE INDEX IF NOT EXISTS idx_hotel_bookings_dates
    ON hotel_bookings (check_in, check_out)
    INCLUDE (hotel_id, booking_id, rooms);

-- Serves: W05 (Front desk: assign room numbers to July 1 check-ins).
-- Why: Partial B-tree index on check_in WHERE room_number IS NULL.
--      Isolates unassigned check-in rows directly so the update query inspects only pending arrivals.
CREATE INDEX IF NOT EXISTS idx_hotel_bookings_w05
    ON hotel_bookings (check_in)
    WHERE room_number IS NULL;

-- Serves: R18 (Goa reviews) and R24 (Goa hotel rating rankings).
-- Why: Composite B-tree index on city_name and hotel_id with INCLUDE (hotel_name).
--      Facilitates fast joins from hotels in a specific city to their review entities.
CREATE INDEX IF NOT EXISTS idx_hotels_city
    ON hotels (city_name, hotel_id)
    INCLUDE (hotel_name);

-- ---------------------------------------------------------------------
-- 3. BOOKINGS LIFECYCLE & ANALYTICS INDEXES
-- ---------------------------------------------------------------------

-- Serves: R05 ("My Trips": customer 1021's upcoming confirmed trips).
-- Why: Composite covering B-tree index on (customer_id, status).
--      Turns a 144k sequential scan into an O(log N) lookup; INCLUDE clause supplies booking details.
CREATE INDEX IF NOT EXISTS idx_bookings_customer_status
    ON bookings (customer_id, status)
    INCLUDE (booking_ref, booking_type, total_amount);

-- Serves: R11 (Pending payment timeout sweeper) and W02 (Payment gateway confirm callback).
-- Why: Partial B-tree index on (booking_id, booked_at) for status = 'PENDING_PAYMENT'.
--      Enables subquery min(booking_id) in W02 to execute in 0.02 ms and sweeps expired checkouts fast.
CREATE INDEX IF NOT EXISTS idx_bookings_pending_payment
    ON bookings (booking_id, booked_at)
    WHERE status = 'PENDING_PAYMENT';

-- Serves: R12 (Finance: 2026 monthly revenue by booking type).
-- Why: Partial covering B-tree index on (booked_at, booking_type) with total_amount WHERE status <> 'CANCELLED'.
--      Powers an Index Only Scan across sargable 2026 date boundaries without reading heap blocks.
CREATE INDEX IF NOT EXISTS idx_bookings_revenue_2026
    ON bookings (booked_at, booking_type)
    INCLUDE (total_amount)
    WHERE status <> 'CANCELLED';

-- Serves: R13 (Marketing: promotional coupons that have never been used).
-- Why: Partial B-tree index on (coupon_code) WHERE coupon_code IS NOT NULL.
--      Supports two-valued boolean anti-join (NOT EXISTS) via Index Only Scan on coupons used in bookings.
CREATE INDEX IF NOT EXISTS idx_bookings_coupon_code
    ON bookings (coupon_code)
    WHERE coupon_code IS NOT NULL;

-- Serves: R17 (Loyalty: customers with 3+ completed trips in 2026).
-- Why: Partial composite B-tree index on (customer_id, total_amount) for status = 'COMPLETED'
--      and booked_at >= '2026-01-01'. Restricts group aggregation strictly to qualified trips.
CREATE INDEX IF NOT EXISTS idx_bookings_completed_2026
    ON bookings (customer_id, total_amount)
    WHERE status = 'COMPLETED' AND booked_at >= '2026-01-01';

-- Serves: R09 (Top routes June 2026), R20 (Daily running bookings), R22 (Deep pagination), R25 (Last-minute).
-- Why: Composite B-tree index on (booked_at DESC, booking_id DESC) with INCLUDE for projection attributes.
--      Provides pre-sorted chronological ordering to eliminate sort nodes and power keyset/offset pagination.
CREATE INDEX IF NOT EXISTS idx_bookings_booked_at_desc
    ON bookings (booked_at DESC, booking_id DESC)
    INCLUDE (booking_ref, booking_type, status, total_amount);

-- Serves: R01, R04, R07, R15, W02 (Covering lookups on booking status during joins).
-- Why: Covering B-tree index on booking_id with INCLUDE (booking_ref, status).
--      Allows joined queries to evaluate cancellation filters directly inside the index without heap lookups.
CREATE INDEX IF NOT EXISTS idx_bookings_id_ref_status
    ON bookings (booking_id)
    INCLUDE (booking_ref, status);

-- ---------------------------------------------------------------------
-- 4. REVIEWS, PASSENGERS & CUSTOMERS INDEXES
-- ---------------------------------------------------------------------

-- Serves: R18 (Hotel reviews mentioning keyword 'breakfast').
-- Why: Trigram GIN index (gin_trgm_ops) via pg_trgm extension on review_text.
--      Transforms arbitrary substring matching (ILIKE '%breakfast%') from a full table scan into an index search.
CREATE INDEX IF NOT EXISTS idx_hotel_reviews_text_trgm
    ON hotel_reviews USING gin (review_text gin_trgm_ops);

-- Serves: R24 (Hotel ranking: average rating of hotels with at least 5 reviews).
-- Why: Composite B-tree index on (hotel_id, rating).
--      Allows grouping and averaging review scores per hotel property via fast index traversal.
CREATE INDEX IF NOT EXISTS idx_hotel_reviews_hotel_rating
    ON hotel_reviews (hotel_id, rating);

-- Serves: R21 (Concessions: senior-citizen passengers 60+ per route in 2026).
-- Why: Partial B-tree index on foreign key booking_id WHERE age >= 60.
--      Filters out >75% of passengers who do not qualify for senior citizen concessions.
CREATE INDEX IF NOT EXISTS idx_passengers_seniors
    ON passengers (booking_id)
    WHERE age >= 60;

-- Serves: R23 (Customer authentication: find customer by case-insensitive email).
-- Why: Functional expression B-tree index on lower(email) with covering customer details.
--      Resolves lower(email) = ... directly in 0.1 ms rather than sequentially scanning all customers.
CREATE INDEX IF NOT EXISTS idx_customers_lower_email
    ON customers (lower(email))
    INCLUDE (customer_id, full_name, loyalty_tier);

-- Serves: R07 (Passenger manifest) and R19 (Monthly flight passenger aggregation).
-- Why: Covering B-tree index on booking_id with INCLUDE (full_name, age, gender, seat_no).
--      Delivers full passenger manifests directly via Index Only Scan.
CREATE INDEX IF NOT EXISTS idx_passengers_manifest
    ON passengers (booking_id)
    INCLUDE (full_name, age, gender, seat_no);

-- Refresh database statistics so the planner utilizes newly added indexes
ANALYZE;
