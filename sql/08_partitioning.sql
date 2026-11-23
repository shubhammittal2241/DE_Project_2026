-- Phase 5: Range Partitioning & Archival for Bookings
-- Schema: mmt_partitioned

DROP SCHEMA IF EXISTS mmt_partitioned CASCADE;
CREATE SCHEMA mmt_partitioned;
SET search_path TO mmt_partitioned;

-- 1. Bookings partitioned table by range on booked_at
-- Note: In PG, unique/primary key on partitioned tables must include the partition key column
CREATE TABLE bookings (
    booking_id INT NOT NULL,
    booking_ref VARCHAR(20) NOT NULL,
    customer_id INT NOT NULL,
    booking_type VARCHAR(10) NOT NULL,
    booked_at TIMESTAMPTZ NOT NULL,
    total_amount NUMERIC(10,2) NOT NULL,
    coupon_code VARCHAR(30),
    discount NUMERIC(10,2) NOT NULL DEFAULT 0.00,
    payment_method VARCHAR(20) NOT NULL,
    status VARCHAR(20) NOT NULL,
    cancelled_at TIMESTAMPTZ,
    refund_amount NUMERIC(10,2),
    PRIMARY KEY (booking_id, booked_at),
    CONSTRAINT chk_part_bookings_type CHECK (booking_type IN ('FLIGHT', 'HOTEL')),
    CONSTRAINT chk_part_bookings_payment_method CHECK (payment_method IN ('CARD', 'NETBANKING', 'UPI', 'WALLET', 'EMI')),
    CONSTRAINT chk_part_bookings_status CHECK (status IN ('CONFIRMED', 'COMPLETED', 'CANCELLED', 'PENDING_PAYMENT')),
    CONSTRAINT chk_part_bookings_amount CHECK (total_amount >= 0),
    CONSTRAINT chk_part_bookings_discount CHECK (discount >= 0),
    CONSTRAINT chk_part_bookings_cancellation CHECK (
        (status = 'CANCELLED' AND cancelled_at IS NOT NULL AND refund_amount IS NOT NULL) OR
        (status <> 'CANCELLED' AND cancelled_at IS NULL AND refund_amount IS NULL)
    ),
    CONSTRAINT chk_part_bookings_refund CHECK (refund_amount IS NULL OR refund_amount <= total_amount)
) PARTITION BY RANGE (booked_at);

-- 2. Quarterly partitions (2025 - 2026) and a default partition
CREATE TABLE bookings_2025_q1 PARTITION OF bookings
    FOR VALUES FROM ('2025-01-01 00:00:00+05:30') TO ('2025-04-01 00:00:00+05:30');

CREATE TABLE bookings_2025_q2 PARTITION OF bookings
    FOR VALUES FROM ('2025-04-01 00:00:00+05:30') TO ('2025-07-01 00:00:00+05:30');

CREATE TABLE bookings_2025_q3 PARTITION OF bookings
    FOR VALUES FROM ('2025-07-01 00:00:00+05:30') TO ('2025-10-01 00:00:00+05:30');

CREATE TABLE bookings_2025_q4 PARTITION OF bookings
    FOR VALUES FROM ('2025-10-01 00:00:00+05:30') TO ('2026-01-01 00:00:00+05:30');

CREATE TABLE bookings_2026_q1 PARTITION OF bookings
    FOR VALUES FROM ('2026-01-01 00:00:00+05:30') TO ('2026-04-01 00:00:00+05:30');

CREATE TABLE bookings_2026_q2 PARTITION OF bookings
    FOR VALUES FROM ('2026-04-01 00:00:00+05:30') TO ('2026-07-01 00:00:00+05:30');

CREATE TABLE bookings_2026_q3 PARTITION OF bookings
    FOR VALUES FROM ('2026-07-01 00:00:00+05:30') TO ('2026-10-01 00:00:00+05:30');

CREATE TABLE bookings_2026_q4 PARTITION OF bookings
    FOR VALUES FROM ('2026-10-01 00:00:00+05:30') TO ('2027-01-01 00:00:00+05:30');

CREATE TABLE bookings_default PARTITION OF bookings DEFAULT;

-- 3. Local partition indexes
CREATE INDEX idx_part_booked_at_keyset
    ON bookings (booked_at DESC, booking_id DESC)
    INCLUDE (booking_ref, booking_type, status, total_amount);

CREATE INDEX idx_part_customer_status
    ON bookings (customer_id, status)
    INCLUDE (booking_ref, booking_type, total_amount);

CREATE INDEX idx_part_pending_payment
    ON bookings (booking_id, booked_at)
    WHERE status = 'PENDING_PAYMENT';

-- 4. Co-partition flight_bookings on booked_at
CREATE TABLE flight_bookings (
    booking_id INT NOT NULL,
    booked_at TIMESTAMPTZ NOT NULL,
    flight_id INT NOT NULL,
    cabin VARCHAR(20) NOT NULL,
    passengers INT NOT NULL,
    fare_paid NUMERIC(10,2) NOT NULL,
    PRIMARY KEY (booking_id, booked_at)
) PARTITION BY RANGE (booked_at);

CREATE TABLE fb_2025_q1 PARTITION OF flight_bookings
    FOR VALUES FROM ('2025-01-01 00:00:00+05:30') TO ('2025-04-01 00:00:00+05:30');
CREATE TABLE fb_2025_q2 PARTITION OF flight_bookings
    FOR VALUES FROM ('2025-04-01 00:00:00+05:30') TO ('2025-07-01 00:00:00+05:30');
CREATE TABLE fb_2025_q3 PARTITION OF flight_bookings
    FOR VALUES FROM ('2025-07-01 00:00:00+05:30') TO ('2025-10-01 00:00:00+05:30');
CREATE TABLE fb_2025_q4 PARTITION OF flight_bookings
    FOR VALUES FROM ('2025-10-01 00:00:00+05:30') TO ('2026-01-01 00:00:00+05:30');
CREATE TABLE fb_2026_q1 PARTITION OF flight_bookings
    FOR VALUES FROM ('2026-01-01 00:00:00+05:30') TO ('2026-04-01 00:00:00+05:30');
CREATE TABLE fb_2026_q2 PARTITION OF flight_bookings
    FOR VALUES FROM ('2026-04-01 00:00:00+05:30') TO ('2026-07-01 00:00:00+05:30');
CREATE TABLE fb_2026_q3 PARTITION OF flight_bookings
    FOR VALUES FROM ('2026-07-01 00:00:00+05:30') TO ('2026-10-01 00:00:00+05:30');
CREATE TABLE fb_2026_q4 PARTITION OF flight_bookings
    FOR VALUES FROM ('2026-10-01 00:00:00+05:30') TO ('2027-01-01 00:00:00+05:30');
CREATE TABLE fb_default PARTITION OF flight_bookings DEFAULT;

CREATE INDEX idx_fb_part_flight ON flight_bookings (flight_id);

ALTER TABLE flight_bookings
    ADD CONSTRAINT fk_fb_part_bookings
    FOREIGN KEY (booking_id, booked_at) REFERENCES bookings (booking_id, booked_at) ON DELETE CASCADE;

-- 5. Populate partitioned tables from mmt schema
INSERT INTO bookings
SELECT * FROM mmt.bookings;

INSERT INTO flight_bookings
SELECT fb.booking_id, b.booked_at, fb.flight_id, fb.cabin, fb.passengers, fb.fare_paid
FROM mmt.flight_bookings fb
JOIN mmt.bookings b ON b.booking_id = fb.booking_id;

ANALYZE bookings;
ANALYZE flight_bookings;

-- 6. Partition pruning tests

-- Test 6A: Single-quarter range (June 2026 - only scans bookings_2026_q2)
EXPLAIN (ANALYZE, BUFFERS)
SELECT count(*), sum(total_amount)
FROM bookings
WHERE booked_at >= '2026-06-01 00:00:00+05:30'
  AND booked_at <  '2026-07-01 00:00:00+05:30';

-- Test 6B: Point lookup on timestamp (scans only bookings_2025_q1)
EXPLAIN (ANALYZE, BUFFERS)
SELECT booking_id, booking_ref, total_amount
FROM bookings
WHERE booked_at = '2025-02-15 14:30:00+05:30';

-- Test 6C: Multi-quarter range (Nov 2025 to Feb 2026 - scans q4 2025 and q1 2026)
EXPLAIN (ANALYZE, BUFFERS)
SELECT date_trunc('month', booked_at) AS m, count(*)
FROM bookings
WHERE booked_at >= '2025-11-01 00:00:00+05:30'
  AND booked_at <  '2026-03-01 00:00:00+05:30'
GROUP BY 1;

-- Test 6D: Keyset pagination on partitioned table
EXPLAIN (ANALYZE, BUFFERS)
SELECT booking_id, booking_ref, booking_type, status, total_amount, booked_at
FROM bookings
WHERE (booked_at, booking_id) < ('2025-06-18 22:12:10+05:30', 46409)
ORDER BY booked_at DESC, booking_id DESC
LIMIT 25;

-- 7. Archival demo: Detach & attach 2025 Q1 partition

-- Step 1: Detach child partition
ALTER TABLE flight_bookings DETACH PARTITION fb_2025_q1;

-- Step 2: Drop inherited foreign key on standalone child
ALTER TABLE fb_2025_q1 DROP CONSTRAINT fk_fb_part_bookings;

-- Step 3: Detach master partition
ALTER TABLE bookings DETACH PARTITION bookings_2025_q1;

-- Step 4: Add direct foreign key between detached archive tables
ALTER TABLE fb_2025_q1
    ADD CONSTRAINT fk_fb_archived_bookings
    FOREIGN KEY (booking_id, booked_at) REFERENCES bookings_2025_q1 (booking_id, booked_at) ON DELETE CASCADE;

-- Step 5: Verify detached data is excluded from main table
EXPLAIN (ANALYZE, BUFFERS)
SELECT count(*) FROM bookings WHERE booked_at >= '2025-01-01' AND booked_at < '2025-04-01';

-- Step 6: Re-attach partitions
ALTER TABLE fb_2025_q1 DROP CONSTRAINT fk_fb_archived_bookings;

ALTER TABLE bookings ATTACH PARTITION bookings_2025_q1
    FOR VALUES FROM ('2025-01-01 00:00:00+05:30') TO ('2025-04-01 00:00:00+05:30');

ALTER TABLE flight_bookings ATTACH PARTITION fb_2025_q1
    FOR VALUES FROM ('2025-01-01 00:00:00+05:30') TO ('2025-04-01 00:00:00+05:30');
