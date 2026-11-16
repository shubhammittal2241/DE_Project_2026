-- =====================================================================
-- MakeMyTrip DBMS Project: Seed Data Loading Script (Phase 2)
-- We load the 12 CSV tables in topological order based on Foreign Key
-- dependencies so PostgreSQL doesn't hit referential integrity errors.
-- =====================================================================

SET search_path TO mmt;

-- 1. Base / Lookup tables (no foreign key dependencies)
-- These must be loaded first so other tables can reference them.
\copy airlines FROM 'seed_data/airlines.csv' WITH (FORMAT csv, HEADER true);
\copy airports FROM 'seed_data/airports.csv' WITH (FORMAT csv, HEADER true);
\copy customers FROM 'seed_data/customers.csv' WITH (FORMAT csv, HEADER true);
\copy coupons FROM 'seed_data/coupons.csv' WITH (FORMAT csv, HEADER true);
\copy hotels FROM 'seed_data/hotels.csv' WITH (FORMAT csv, HEADER true);

-- 2. First-level dependent tables
-- flights references airlines & airports; room_types references hotels; bookings references customers & coupons.
\copy flights FROM 'seed_data/flights.csv' WITH (FORMAT csv, HEADER true);
\copy room_types FROM 'seed_data/room_types.csv' WITH (FORMAT csv, HEADER true);
\copy bookings FROM 'seed_data/bookings.csv' WITH (FORMAT csv, HEADER true);

-- 3. Booking subtype tables (1-to-1 extension of bookings)
-- flight_bookings and hotel_bookings reference bookings.booking_id.
\copy flight_bookings FROM 'seed_data/flight_bookings.csv' WITH (FORMAT csv, HEADER true);
\copy hotel_bookings FROM 'seed_data/hotel_bookings.csv' WITH (FORMAT csv, HEADER true);

-- 4. Leaf / Child entities
-- passengers references flight_bookings; hotel_reviews references hotel_bookings.
\copy passengers FROM 'seed_data/passengers.csv' WITH (FORMAT csv, HEADER true);
\copy hotel_reviews FROM 'seed_data/hotel_reviews.csv' WITH (FORMAT csv, HEADER true);

-- Refresh table statistics so the PostgreSQL query optimizer has accurate estimates
ANALYZE;
