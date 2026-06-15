DROP SCHEMA IF EXISTS oltp CASCADE;
CREATE SCHEMA oltp;
SET search_path = oltp;


CREATE TABLE countries (
    country_code   CHAR(2)      PRIMARY KEY,           -- ISO-3166 alpha-2
    country_name   VARCHAR(100) NOT NULL UNIQUE
);


CREATE TABLE cities (
    city_code      VARCHAR(10)  PRIMARY KEY,
    city_name      VARCHAR(100) NOT NULL,
    country_code   CHAR(2)      NOT NULL REFERENCES countries(country_code),
    UNIQUE (city_name, country_code)
);


CREATE TABLE hotel_categories (
    category_code  VARCHAR(10)  PRIMARY KEY,
    category_name  VARCHAR(50)  NOT NULL UNIQUE,
    stars          SMALLINT     CHECK (stars BETWEEN 1 AND 5)
);


CREATE TABLE hotels (
    hotel_code     VARCHAR(10)  PRIMARY KEY,
    hotel_name     VARCHAR(150) NOT NULL,
    city_code      VARCHAR(10)  NOT NULL REFERENCES cities(city_code),
    category_code  VARCHAR(10)  NOT NULL REFERENCES hotel_categories(category_code),
    address        VARCHAR(255),
    phone          VARCHAR(30),
    email          VARCHAR(100),
    check_in_time  TIME         NOT NULL DEFAULT '14:00',
    check_out_time TIME         NOT NULL DEFAULT '12:00'
);


CREATE TABLE room_types (
    room_type_code VARCHAR(10)  PRIMARY KEY,
    type_name      VARCHAR(50)  NOT NULL UNIQUE,
    max_guests     SMALLINT     NOT NULL CHECK (max_guests > 0),
    description    TEXT
);


CREATE TABLE rooms (
    room_id        SERIAL       PRIMARY KEY,
    hotel_code     VARCHAR(10)  NOT NULL REFERENCES hotels(hotel_code),
    room_number    VARCHAR(10)  NOT NULL,
    room_type_code VARCHAR(10)  NOT NULL REFERENCES room_types(room_type_code),
    floor          SMALLINT,
    price_per_night NUMERIC(10,2) NOT NULL CHECK (price_per_night > 0),
    is_active      BOOLEAN      NOT NULL DEFAULT TRUE,
    UNIQUE (hotel_code, room_number)
);


CREATE TABLE guests (
    guest_code     VARCHAR(20)  PRIMARY KEY,           -- passport / national ID
    first_name     VARCHAR(80)  NOT NULL,
    last_name      VARCHAR(80)  NOT NULL,
    email          VARCHAR(100) NOT NULL UNIQUE,
    phone          VARCHAR(30),
    date_of_birth  DATE,
    country_code   CHAR(2)      REFERENCES countries(country_code),
    loyalty_points INTEGER      NOT NULL DEFAULT 0 CHECK (loyalty_points >= 0),
    registered_at  TIMESTAMP    NOT NULL DEFAULT NOW()
);


CREATE TABLE booking_statuses (
    status_code    VARCHAR(20)  PRIMARY KEY,
    status_name    VARCHAR(50)  NOT NULL UNIQUE,
    is_terminal    BOOLEAN      NOT NULL DEFAULT FALSE   -- no further changes allowed
);


CREATE TABLE bookings (
    booking_code   VARCHAR(20)  PRIMARY KEY,            -- e.g. BK-2024-000001
    guest_code     VARCHAR(20)  NOT NULL REFERENCES guests(guest_code),
    room_id        INTEGER      NOT NULL REFERENCES rooms(room_id),
    check_in_date  DATE         NOT NULL,
    check_out_date DATE         NOT NULL,
    guests_count   SMALLINT     NOT NULL DEFAULT 1 CHECK (guests_count > 0),
    total_price    NUMERIC(12,2) NOT NULL CHECK (total_price >= 0),
    status_code    VARCHAR(20)  NOT NULL REFERENCES booking_statuses(status_code),
    booked_at      TIMESTAMP    NOT NULL DEFAULT NOW(),
    notes          TEXT,
    CONSTRAINT chk_dates CHECK (check_out_date > check_in_date)
);


CREATE TABLE payments (
    payment_code   VARCHAR(30)  PRIMARY KEY,
    booking_code   VARCHAR(20)  NOT NULL REFERENCES bookings(booking_code),
    amount         NUMERIC(12,2) NOT NULL CHECK (amount > 0),
    payment_method VARCHAR(30)  NOT NULL
                   CHECK (payment_method IN ('credit_card','debit_card','cash','bank_transfer','online_wallet')),
    payment_date   TIMESTAMP    NOT NULL DEFAULT NOW(),
    is_refund      BOOLEAN      NOT NULL DEFAULT FALSE,
    notes          TEXT
);

CREATE INDEX idx_bookings_guest      ON bookings(guest_code);
CREATE INDEX idx_bookings_room       ON bookings(room_id);
CREATE INDEX idx_bookings_dates      ON bookings(check_in_date, check_out_date);
CREATE INDEX idx_bookings_status     ON bookings(status_code);
CREATE INDEX idx_rooms_hotel         ON rooms(hotel_code);
CREATE INDEX idx_payments_booking    ON payments(booking_code);
CREATE INDEX idx_hotels_city         ON hotels(city_code);
