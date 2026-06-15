-- ============================================================
-- OLAP QUERIES — Hotel Booking DWH
-- ============================================================
SET search_path = olap;

-- ── Query 1 ─────────────────────────────────────────────────
-- Revenue by quarter, country, and hotel category (CUBE-style)
-- Question: What is our revenue breakdown by region and time?
-- ────────────────────────────────────────────────────────────
SELECT
    dd.year,
    dd.quarter,
    dl.country_name,
    dh.category_name,
    COUNT(fb.booking_fact_id)           AS bookings,
    SUM(fb.total_price)                 AS total_revenue,
    SUM(fb.nights)                      AS total_nights,
    ROUND(AVG(fb.avg_price_per_night), 2) AS avg_nightly_rate
FROM fact_bookings fb
JOIN dim_date        dd  ON dd.date_key    = fb.check_in_date_key
JOIN dim_hotel       dh  ON dh.hotel_key   = fb.hotel_key
JOIN dim_location    dl  ON dl.location_key = dh.location_key
JOIN dim_booking_status ds ON ds.status_key = fb.status_key
WHERE ds.is_terminal = TRUE
  AND ds.status_code  = 'COMPLETED'
GROUP BY dd.year, dd.quarter, dl.country_name, dh.category_name
ORDER BY dd.year, dd.quarter, total_revenue DESC;


-- ── Query 2 ─────────────────────────────────────────────────
-- Loyalty tier analysis — bookings and spend per tier (SCD Type 2)
-- Question: Do Gold/Platinum guests book more and spend more?
-- ────────────────────────────────────────────────────────────
SELECT
    dg.loyalty_tier,
    COUNT(DISTINCT dg.guest_code)         AS unique_guests,
    COUNT(fb.booking_fact_id)             AS total_bookings,
    ROUND(
        COUNT(fb.booking_fact_id)::NUMERIC
        / NULLIF(COUNT(DISTINCT dg.guest_code), 0), 2
    )                                     AS avg_bookings_per_guest,
    SUM(fb.total_price)                   AS total_revenue,
    ROUND(AVG(fb.total_price), 2)         AS avg_booking_value
FROM fact_bookings fb
JOIN dim_guest dg ON dg.guest_key = fb.guest_key
GROUP BY dg.loyalty_tier
ORDER BY
    CASE dg.loyalty_tier
        WHEN 'Platinum' THEN 1
        WHEN 'Gold'     THEN 2
        WHEN 'Silver'   THEN 3
        ELSE 4
    END;


-- ── Query 3 ─────────────────────────────────────────────────
-- Monthly payment trends by method (year-over-year)
-- Question: Which payment methods are growing?
-- ────────────────────────────────────────────────────────────
SELECT
    dd.year,
    dd.month_name,
    dd.month_num,
    dpm.method_name,
    COUNT(fp.payment_fact_id)             AS transaction_count,
    SUM(fp.net_amount)                    AS net_revenue,
    SUM(fp.amount) FILTER (WHERE fp.is_refund) AS refunded
FROM fact_payments fp
JOIN dim_date           dd  ON dd.date_key          = fp.payment_date_key
JOIN dim_payment_method dpm ON dpm.payment_method_key = fp.payment_method_key
GROUP BY dd.year, dd.month_name, dd.month_num, dpm.method_name
ORDER BY dd.year, dd.month_num, net_revenue DESC;


-- ── Query 4 ─────────────────────────────────────────────────
-- Hotel occupancy rate by month
-- Question: Which months are the busiest for each hotel?
-- ────────────────────────────────────────────────────────────
WITH monthly_nights AS (
    SELECT
        fb.hotel_key,
        dd.year,
        dd.month_num,
        dd.month_name,
        SUM(fb.nights) AS nights_booked
    FROM fact_bookings fb
    JOIN dim_date dd ON dd.date_key = fb.check_in_date_key
    JOIN dim_booking_status ds ON ds.status_key = fb.status_key
    WHERE ds.status_code IN ('COMPLETED', 'CHECKED_IN')
    GROUP BY fb.hotel_key, dd.year, dd.month_num, dd.month_name
),
hotel_capacity AS (
    -- approximate: count active rooms per hotel from OLTP
    SELECT r.hotel_code, COUNT(*) AS room_count
    FROM oltp.rooms r WHERE r.is_active = TRUE
    GROUP BY r.hotel_code
)
SELECT
    dh.hotel_name,
    mn.year,
    mn.month_name,
    mn.nights_booked,
    hc.room_count,
    -- days in month × rooms = total available room-nights
    ROUND(
        100.0 * mn.nights_booked
        / NULLIF(hc.room_count * 30, 0), 1
    ) AS occupancy_rate_pct
FROM monthly_nights mn
JOIN dim_hotel dh ON dh.hotel_key = mn.hotel_key
JOIN hotel_capacity hc ON hc.hotel_code = dh.hotel_code
ORDER BY dh.hotel_name, mn.year, mn.month_num;


-- ── Query 5 ─────────────────────────────────────────────────
-- Room type revenue mix — which types drive the most income?
-- ────────────────────────────────────────────────────────────
SELECT
    drt.type_name,
    COUNT(fb.booking_fact_id)              AS bookings,
    SUM(fb.nights)                         AS total_nights,
    SUM(fb.total_price)                    AS total_revenue,
    ROUND(AVG(fb.avg_price_per_night), 2)  AS avg_nightly_rate,
    ROUND(
        100.0 * SUM(fb.total_price)
        / SUM(SUM(fb.total_price)) OVER (), 1
    )                                      AS revenue_share_pct
FROM fact_bookings fb
JOIN dim_room_type drt ON drt.room_type_key = fb.room_type_key
GROUP BY drt.type_name
ORDER BY total_revenue DESC;
