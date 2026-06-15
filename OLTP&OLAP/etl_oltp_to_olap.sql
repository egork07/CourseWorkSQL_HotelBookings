-- ============================================================
-- ETL: OLTP → OLAP  (idempotent / incremental)
-- Run order: this script assumes both schemas exist in same DB.
-- Previously loaded records are NOT overwritten.
-- ============================================================
SET search_path = olap;

-- ============================================================
-- STEP 1 — dim_date  (populate 2023-01-01 … 2027-12-31)
-- ============================================================
INSERT INTO olap.dim_date (
    date_key, full_date, day_of_week, day_name,
    day_of_month, day_of_year, week_of_year,
    month_num, month_name, quarter, year, is_weekend
)
SELECT
    TO_CHAR(d, 'YYYYMMDD')::INTEGER,
    d::DATE,
    EXTRACT(ISODOW FROM d)::SMALLINT,
    TO_CHAR(d, 'Day'),
    EXTRACT(DAY   FROM d)::SMALLINT,
    EXTRACT(DOY   FROM d)::SMALLINT,
    EXTRACT(WEEK  FROM d)::SMALLINT,
    EXTRACT(MONTH FROM d)::SMALLINT,
    TO_CHAR(d, 'Month'),
    EXTRACT(QUARTER FROM d)::SMALLINT,
    EXTRACT(YEAR FROM d)::SMALLINT,
    EXTRACT(ISODOW FROM d) IN (6,7)
FROM generate_series('2023-01-01'::DATE, '2027-12-31'::DATE, '1 day') AS t(d)
ON CONFLICT (date_key) DO NOTHING;

-- ============================================================
-- STEP 2 — dim_location
-- ============================================================
INSERT INTO olap.dim_location (city_code, city_name, country_code, country_name)
SELECT
    c.city_code,
    c.city_name,
    c.country_code,
    co.country_name
FROM oltp.cities c
JOIN oltp.countries co ON co.country_code = c.country_code
ON CONFLICT (city_code) DO NOTHING;

-- ============================================================
-- STEP 3 — dim_hotel
-- ============================================================
INSERT INTO olap.dim_hotel (hotel_code, hotel_name, category_code, category_name, stars, location_key)
SELECT
    h.hotel_code,
    h.hotel_name,
    hc.category_code,
    hc.category_name,
    hc.stars,
    dl.location_key
FROM oltp.hotels h
JOIN oltp.hotel_categories hc ON hc.category_code = h.category_code
JOIN olap.dim_location      dl ON dl.city_code     = h.city_code
ON CONFLICT (hotel_code) DO NOTHING;

-- ============================================================
-- STEP 4 — dim_room_type
-- ============================================================
INSERT INTO olap.dim_room_type (room_type_code, type_name, max_guests)
SELECT room_type_code, type_name, max_guests
FROM oltp.room_types
ON CONFLICT (room_type_code) DO NOTHING;

-- ============================================================
-- STEP 5 — dim_guest  (SCD Type 2)
-- Logic:
--   a) Insert brand-new guests (never seen in dim_guest)
--   b) For existing guests: if loyalty_tier changed →
--        close old row (set eff_end_date, is_current=FALSE)
--        insert new row
-- Tier thresholds: <500=Bronze, <2000=Silver, <5000=Gold, >=5000=Platinum
-- ============================================================

-- Helper: tier assignment
CREATE OR REPLACE FUNCTION olap.loyalty_tier(points INTEGER)
RETURNS VARCHAR(20) LANGUAGE sql IMMUTABLE AS $$
    SELECT CASE
        WHEN points < 500  THEN 'Bronze'
        WHEN points < 2000 THEN 'Silver'
        WHEN points < 5000 THEN 'Gold'
        ELSE 'Platinum'
    END;
$$;

-- 5a. New guests
INSERT INTO olap.dim_guest (
    guest_code, first_name, last_name, email,
    country_code, country_name, loyalty_tier, loyalty_points,
    eff_start_date, eff_end_date, is_current
)
SELECT
    g.guest_code, g.first_name, g.last_name, g.email,
    g.country_code, co.country_name,
    olap.loyalty_tier(g.loyalty_points),
    g.loyalty_points,
    CURRENT_DATE, NULL, TRUE
FROM oltp.guests g
LEFT JOIN oltp.countries co ON co.country_code = g.country_code
WHERE NOT EXISTS (
    SELECT 1 FROM olap.dim_guest dg
    WHERE dg.guest_code = g.guest_code
);

-- 5b. Changed loyalty tier → close old, open new
WITH changed AS (
    SELECT g.guest_code
    FROM oltp.guests g
    JOIN olap.dim_guest dg ON dg.guest_code = g.guest_code AND dg.is_current = TRUE
    WHERE olap.loyalty_tier(g.loyalty_points) <> dg.loyalty_tier
)
-- close old rows
UPDATE olap.dim_guest
SET eff_end_date = CURRENT_DATE - 1,
    is_current   = FALSE
WHERE is_current = TRUE
  AND guest_code IN (SELECT guest_code FROM changed);

-- open new rows for changed guests
INSERT INTO olap.dim_guest (
    guest_code, first_name, last_name, email,
    country_code, country_name, loyalty_tier, loyalty_points,
    eff_start_date, eff_end_date, is_current
)
SELECT
    g.guest_code, g.first_name, g.last_name, g.email,
    g.country_code, co.country_name,
    olap.loyalty_tier(g.loyalty_points),
    g.loyalty_points,
    CURRENT_DATE, NULL, TRUE
FROM oltp.guests g
LEFT JOIN oltp.countries co ON co.country_code = g.country_code
-- only for guests where we just closed the old row
WHERE NOT EXISTS (
    SELECT 1 FROM olap.dim_guest dg
    WHERE dg.guest_code = g.guest_code AND dg.is_current = TRUE
);

-- ============================================================
-- STEP 6 — dim_booking_status
-- ============================================================
INSERT INTO olap.dim_booking_status (status_code, status_name, is_terminal)
SELECT status_code, status_name, is_terminal
FROM oltp.booking_statuses
ON CONFLICT (status_code) DO NOTHING;

-- ============================================================
-- STEP 7 — dim_payment_method
-- ============================================================
INSERT INTO olap.dim_payment_method (method_code, method_name)
SELECT DISTINCT
    payment_method,
    INITCAP(REPLACE(payment_method, '_', ' '))
FROM oltp.payments
ON CONFLICT (method_code) DO NOTHING;

-- ============================================================
-- STEP 8 — bridge_booking_guests
-- (primary guest only — expandable for group bookings)
-- ============================================================
INSERT INTO olap.bridge_booking_guests (booking_code, guest_key, is_primary)
SELECT
    b.booking_code,
    dg.guest_key,
    TRUE
FROM oltp.bookings b
JOIN olap.dim_guest dg ON dg.guest_code = b.guest_code AND dg.is_current = TRUE
WHERE NOT EXISTS (
    SELECT 1 FROM olap.bridge_booking_guests bbg
    WHERE bbg.booking_code = b.booking_code
      AND bbg.guest_key    = dg.guest_key
);

-- ============================================================
-- STEP 9 — fact_bookings
-- ============================================================
INSERT INTO olap.fact_bookings (
    booking_code,
    hotel_key, room_type_key, guest_key,
    booked_date_key, check_in_date_key, check_out_date_key,
    status_key,
    nights, guests_count, total_price, avg_price_per_night
)
SELECT
    b.booking_code,
    dh.hotel_key,
    drt.room_type_key,
    dg.guest_key,
    TO_CHAR(b.booked_at::DATE,      'YYYYMMDD')::INTEGER,
    TO_CHAR(b.check_in_date,  'YYYYMMDD')::INTEGER,
    TO_CHAR(b.check_out_date, 'YYYYMMDD')::INTEGER,
    ds.status_key,
    (b.check_out_date - b.check_in_date)::SMALLINT,
    b.guests_count,
    b.total_price,
    ROUND(b.total_price / NULLIF(b.check_out_date - b.check_in_date, 0), 2)
FROM oltp.bookings b
JOIN oltp.rooms           r   ON r.room_id        = b.room_id
JOIN olap.dim_hotel       dh  ON dh.hotel_code    = r.hotel_code
JOIN olap.dim_room_type   drt ON drt.room_type_code = r.room_type_code
JOIN olap.dim_guest       dg  ON dg.guest_code    = b.guest_code AND dg.is_current = TRUE
JOIN olap.dim_booking_status ds ON ds.status_code = b.status_code
WHERE NOT EXISTS (
    SELECT 1 FROM olap.fact_bookings fb
    WHERE fb.booking_code = b.booking_code
);

-- ============================================================
-- STEP 10 — fact_payments
-- ============================================================
INSERT INTO olap.fact_payments (
    payment_code, booking_code,
    hotel_key, guest_key,
    payment_date_key, payment_method_key,
    amount, is_refund, net_amount
)
SELECT
    p.payment_code,
    p.booking_code,
    dh.hotel_key,
    dg.guest_key,
    TO_CHAR(p.payment_date::DATE, 'YYYYMMDD')::INTEGER,
    dpm.payment_method_key,
    p.amount,
    p.is_refund,
    CASE WHEN p.is_refund THEN -p.amount ELSE p.amount END
FROM oltp.payments p
JOIN oltp.bookings        b   ON b.booking_code   = p.booking_code
JOIN oltp.rooms           r   ON r.room_id        = b.room_id
JOIN olap.dim_hotel       dh  ON dh.hotel_code    = r.hotel_code
JOIN olap.dim_guest       dg  ON dg.guest_code    = b.guest_code AND dg.is_current = TRUE
JOIN olap.dim_payment_method dpm ON dpm.method_code = p.payment_method
WHERE NOT EXISTS (
    SELECT 1 FROM olap.fact_payments fp
    WHERE fp.payment_code = p.payment_code
);

-- ============================================================
-- SUMMARY
-- ============================================================
DO $$
BEGIN
    RAISE NOTICE 'ETL complete.';
    RAISE NOTICE 'dim_date:            %', (SELECT COUNT(*) FROM olap.dim_date);
    RAISE NOTICE 'dim_location:        %', (SELECT COUNT(*) FROM olap.dim_location);
    RAISE NOTICE 'dim_hotel:           %', (SELECT COUNT(*) FROM olap.dim_hotel);
    RAISE NOTICE 'dim_room_type:       %', (SELECT COUNT(*) FROM olap.dim_room_type);
    RAISE NOTICE 'dim_guest (rows):    %', (SELECT COUNT(*) FROM olap.dim_guest);
    RAISE NOTICE 'dim_guest (current): %', (SELECT COUNT(*) FROM olap.dim_guest WHERE is_current);
    RAISE NOTICE 'dim_booking_status:  %', (SELECT COUNT(*) FROM olap.dim_booking_status);
    RAISE NOTICE 'dim_payment_method:  %', (SELECT COUNT(*) FROM olap.dim_payment_method);
    RAISE NOTICE 'bridge_booking_guests:%',(SELECT COUNT(*) FROM olap.bridge_booking_guests);
    RAISE NOTICE 'fact_bookings:       %', (SELECT COUNT(*) FROM olap.fact_bookings);
    RAISE NOTICE 'fact_payments:       %', (SELECT COUNT(*) FROM olap.fact_payments);
END $$;
