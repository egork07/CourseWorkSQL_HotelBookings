-- ============================================================
-- OLTP QUERIES — Hotel Booking System
-- ============================================================
SET search_path = oltp;

-- ── Query 1 ─────────────────────────────────────────────────
-- Monthly booking volume and revenue by hotel
-- Question: Which hotels generate the most revenue per month?
-- ────────────────────────────────────────────────────────────
SELECT
    h.hotel_name,
    DATE_TRUNC('month', b.booked_at)::DATE       AS booking_month,
    COUNT(b.booking_code)                         AS total_bookings,
    SUM(b.total_price)                            AS gross_revenue,
    AVG(b.total_price)                            AS avg_booking_value,
    SUM(b.check_out_date - b.check_in_date)       AS total_nights_sold
FROM bookings b
JOIN rooms   r ON r.room_id     = b.room_id
JOIN hotels  h ON h.hotel_code  = r.hotel_code
WHERE b.status_code NOT IN ('CANCELLED', 'NO_SHOW')
GROUP BY h.hotel_name, DATE_TRUNC('month', b.booked_at)
ORDER BY booking_month, gross_revenue DESC;


-- ── Query 2 ─────────────────────────────────────────────────
-- Top 10 most loyal guests with their booking history
-- Question: Who are our best customers?
-- ────────────────────────────────────────────────────────────
SELECT
    g.guest_code,
    g.first_name || ' ' || g.last_name           AS guest_name,
    g.email,
    co.country_name,
    g.loyalty_points,
    COUNT(b.booking_code)                         AS total_bookings,
    SUM(b.total_price)                            AS lifetime_spend,
    AVG(b.total_price)                            AS avg_booking_value,
    MAX(b.check_in_date)                          AS last_stay
FROM guests g
LEFT JOIN bookings b  ON b.guest_code  = g.guest_code
                      AND b.status_code = 'COMPLETED'
LEFT JOIN countries co ON co.country_code = g.country_code
GROUP BY g.guest_code, g.first_name, g.last_name, g.email, co.country_name, g.loyalty_points
ORDER BY lifetime_spend DESC NULLS LAST
LIMIT 10;


-- ── Query 3 ─────────────────────────────────────────────────
-- Room availability check for a given date range
-- Question: Which rooms are free between 2024-06-01 and 2024-06-07?
-- ────────────────────────────────────────────────────────────
SELECT
    h.hotel_name,
    r.room_number,
    rt.type_name         AS room_type,
    r.price_per_night,
    r.floor
FROM rooms r
JOIN hotels    h  ON h.hotel_code    = r.hotel_code
JOIN room_types rt ON rt.room_type_code = r.room_type_code
WHERE r.is_active = TRUE
  AND r.room_id NOT IN (
      SELECT b.room_id
      FROM bookings b
      WHERE b.status_code NOT IN ('CANCELLED', 'NO_SHOW')
        AND b.check_in_date  < '2024-06-07'::DATE
        AND b.check_out_date > '2024-06-01'::DATE
  )
ORDER BY h.hotel_name, r.price_per_night;


-- ── Query 4 ─────────────────────────────────────────────────
-- Cancellation rate by hotel and room type
-- Question: Where do most cancellations happen?
-- ────────────────────────────────────────────────────────────
SELECT
    h.hotel_name,
    rt.type_name                                  AS room_type,
    COUNT(*)                                      AS total_bookings,
    COUNT(*) FILTER (WHERE b.status_code = 'CANCELLED') AS cancelled,
    ROUND(
        100.0 * COUNT(*) FILTER (WHERE b.status_code = 'CANCELLED')
        / NULLIF(COUNT(*), 0), 1
    )                                             AS cancellation_rate_pct
FROM bookings b
JOIN rooms     r  ON r.room_id       = b.room_id
JOIN hotels    h  ON h.hotel_code    = r.hotel_code
JOIN room_types rt ON rt.room_type_code = r.room_type_code
GROUP BY h.hotel_name, rt.type_name
ORDER BY cancellation_rate_pct DESC NULLS LAST;


-- ── Query 5 ─────────────────────────────────────────────────
-- Payment method distribution and refund analysis
-- Question: How are guests paying, and how much is refunded?
-- ────────────────────────────────────────────────────────────
SELECT
    p.payment_method,
    COUNT(*) FILTER (WHERE NOT p.is_refund)       AS total_payments,
    SUM(p.amount) FILTER (WHERE NOT p.is_refund)  AS total_collected,
    COUNT(*) FILTER (WHERE p.is_refund)           AS total_refunds,
    SUM(p.amount) FILTER (WHERE p.is_refund)      AS total_refunded,
    ROUND(
        100.0 * SUM(p.amount) FILTER (WHERE p.is_refund)
        / NULLIF(SUM(p.amount) FILTER (WHERE NOT p.is_refund), 0), 2
    )                                             AS refund_rate_pct
FROM payments p
GROUP BY p.payment_method
ORDER BY total_collected DESC;
