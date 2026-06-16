DROP SCHEMA IF EXISTS olap CASCADE;
CREATE SCHEMA olap;
SET search_path = olap;

CREATE TABLE dim_date (
    date_key        INTEGER      PRIMARY KEY,           -- YYYYMMDD
    full_date       DATE         NOT NULL UNIQUE,
    day_of_week     SMALLINT     NOT NULL,              -- 1=Mon … 7=Sun
    day_name        VARCHAR(10)  NOT NULL,
    day_of_month    SMALLINT     NOT NULL,
    day_of_year     SMALLINT     NOT NULL,
    week_of_year    SMALLINT     NOT NULL,
    month_num       SMALLINT     NOT NULL,
    month_name      VARCHAR(10)  NOT NULL,
    quarter         SMALLINT     NOT NULL,
    year            SMALLINT     NOT NULL,
    is_weekend      BOOLEAN      NOT NULL,
    is_holiday      BOOLEAN      NOT NULL DEFAULT FALSE
);


CREATE TABLE dim_location (
    location_key    SERIAL       PRIMARY KEY,
    city_code       VARCHAR(10)  NOT NULL,
    city_name       VARCHAR(100) NOT NULL,
    country_code    CHAR(2)      NOT NULL,
    country_name    VARCHAR(100) NOT NULL,
    UNIQUE (city_code)
);


CREATE TABLE dim_hotel (
    hotel_key       SERIAL       PRIMARY KEY,
    hotel_code      VARCHAR(10)  NOT NULL UNIQUE,
    hotel_name      VARCHAR(150) NOT NULL,
    category_code   VARCHAR(10)  NOT NULL,
    category_name   VARCHAR(50)  NOT NULL,
    stars           SMALLINT,
    location_key    INTEGER      NOT NULL REFERENCES dim_location(location_key)
);


CREATE TABLE dim_room_type (
    room_type_key   SERIAL       PRIMARY KEY,
    room_type_code  VARCHAR(10)  NOT NULL UNIQUE,
    type_name       VARCHAR(50)  NOT NULL,
    max_guests      SMALLINT     NOT NULL
);


CREATE TABLE dim_guest (
    guest_key       SERIAL       PRIMARY KEY,           -- surrogate key
    guest_code      VARCHAR(20)  NOT NULL,              -- natural key from OLTP
    first_name      VARCHAR(80)  NOT NULL,
    last_name       VARCHAR(80)  NOT NULL,
    email           VARCHAR(100) NOT NULL,
    country_code    CHAR(2),
    country_name    VARCHAR(100),
    loyalty_tier    VARCHAR(20)  NOT NULL,              -- Bronze/Silver/Gold/Platinum
    loyalty_points  INTEGER      NOT NULL,
    -- SCD Type 2 metadata
    eff_start_date  DATE         NOT NULL,
    eff_end_date    DATE,                               -- NULL = currently active
    is_current      BOOLEAN      NOT NULL DEFAULT TRUE
);

CREATE INDEX idx_dguest_code    ON dim_guest(guest_code);
CREATE INDEX idx_dguest_current ON dim_guest(guest_code, is_current);


CREATE TABLE dim_payment_method (
    payment_method_key SERIAL    PRIMARY KEY,
    method_code        VARCHAR(30) NOT NULL UNIQUE,
    method_name        VARCHAR(60) NOT NULL
);


CREATE TABLE dim_booking_status (
    status_key      SERIAL       PRIMARY KEY,
    status_code     VARCHAR(20)  NOT NULL UNIQUE,
    status_name     VARCHAR(50)  NOT NULL,
    is_terminal     BOOLEAN      NOT NULL
);


CREATE TABLE bridge_booking_guests (
    booking_code    VARCHAR(20)  NOT NULL,
    guest_key       INTEGER      NOT NULL REFERENCES dim_guest(guest_key),
    is_primary      BOOLEAN      NOT NULL DEFAULT FALSE,  -- the person who booked
    PRIMARY KEY (booking_code, guest_key)
);


CREATE TABLE fact_bookings (
    booking_fact_id     SERIAL       PRIMARY KEY,
    booking_code        VARCHAR(20)  NOT NULL UNIQUE,
    -- dimensions
    hotel_key           INTEGER      NOT NULL REFERENCES dim_hotel(hotel_key),
    room_type_key       INTEGER      NOT NULL REFERENCES dim_room_type(room_type_key),
    guest_key           INTEGER      NOT NULL REFERENCES dim_guest(guest_key),   -- primary guest SCD key
    booked_date_key     INTEGER      NOT NULL REFERENCES dim_date(date_key),
    check_in_date_key   INTEGER      NOT NULL REFERENCES dim_date(date_key),
    check_out_date_key  INTEGER      NOT NULL REFERENCES dim_date(date_key),
    status_key          INTEGER      NOT NULL REFERENCES dim_booking_status(status_key),
    -- measures (aggregated / derived)
    nights              SMALLINT     NOT NULL,
    guests_count        SMALLINT     NOT NULL,
    total_price         NUMERIC(12,2) NOT NULL,
    avg_price_per_night NUMERIC(10,2) NOT NULL
);

CREATE INDEX idx_fbookings_hotel    ON fact_bookings(hotel_key);
CREATE INDEX idx_fbookings_guest    ON fact_bookings(guest_key);
CREATE INDEX idx_fbookings_checkin  ON fact_bookings(check_in_date_key);
CREATE INDEX idx_fbookings_status   ON fact_bookings(status_key);


CREATE TABLE fact_payments (
    payment_fact_id     SERIAL       PRIMARY KEY,
    payment_code        VARCHAR(30)  NOT NULL UNIQUE,
    booking_code        VARCHAR(20)  NOT NULL,
    -- dimensions
    hotel_key           INTEGER      NOT NULL REFERENCES dim_hotel(hotel_key),
    guest_key           INTEGER      NOT NULL REFERENCES dim_guest(guest_key),
    payment_date_key    INTEGER      NOT NULL REFERENCES dim_date(date_key),
    payment_method_key  INTEGER      NOT NULL REFERENCES dim_payment_method(payment_method_key),
    -- measures
    amount              NUMERIC(12,2) NOT NULL,
    is_refund           BOOLEAN      NOT NULL DEFAULT FALSE,
    net_amount          NUMERIC(12,2) NOT NULL  -- negative when is_refund = TRUE
);

CREATE INDEX idx_fpayments_hotel   ON fact_payments(hotel_key);
CREATE INDEX idx_fpayments_guest   ON fact_payments(guest_key);
CREATE INDEX idx_fpayments_date    ON fact_payments(payment_date_key);
CREATE INDEX idx_fpayments_method  ON fact_payments(payment_method_key);
