SET search_path = oltp;

CREATE TEMP TABLE stg_countries        (LIKE oltp.countries);
CREATE TEMP TABLE stg_cities           (LIKE oltp.cities);
CREATE TEMP TABLE stg_hotel_categories (LIKE oltp.hotel_categories);
CREATE TEMP TABLE stg_hotels           (LIKE oltp.hotels);
CREATE TEMP TABLE stg_room_types       (LIKE oltp.room_types);
CREATE TEMP TABLE stg_rooms            (LIKE oltp.rooms);
CREATE TEMP TABLE stg_booking_statuses (LIKE oltp.booking_statuses);
CREATE TEMP TABLE stg_guests           (LIKE oltp.guests);
CREATE TEMP TABLE stg_bookings         (LIKE oltp.bookings);
CREATE TEMP TABLE stg_payments         (LIKE oltp.payments);

COPY stg_countries        FROM '/Users/egor/CourseWorkSQL/CSV/countries.csv'        CSV HEADER;
COPY stg_cities           FROM '/Users/egor/CourseWorkSQL/CSV/cities.csv'           CSV HEADER;
COPY stg_hotel_categories FROM '/Users/egor/CourseWorkSQL/CSV/hotel_categories.csv' CSV HEADER;
COPY stg_hotels           FROM '/Users/egor/CourseWorkSQL/CSV/hotels.csv'           CSV HEADER;
COPY stg_room_types       FROM '/Users/egor/CourseWorkSQL/CSV/room_types.csv'       CSV HEADER;
COPY stg_rooms            FROM '/Users/egor/CourseWorkSQL/CSV/rooms.csv'            CSV HEADER;
COPY stg_booking_statuses FROM '/Users/egor/CourseWorkSQL/CSV/booking_statuses.csv' CSV HEADER;
COPY stg_guests           FROM '/Users/egor/CourseWorkSQL/CSV/guests.csv'           CSV HEADER;
COPY stg_bookings         FROM '/Users/egor/CourseWorkSQL/CSV/bookings.csv'         CSV HEADER;
COPY stg_payments         FROM '/Users/egor/CourseWorkSQL/CSV/payments.csv'         CSV HEADER;

INSERT INTO oltp.countries        SELECT * FROM stg_countries        ON CONFLICT (country_code)   DO NOTHING;
INSERT INTO oltp.cities           SELECT * FROM stg_cities           ON CONFLICT (city_code)      DO NOTHING;
INSERT INTO oltp.hotel_categories SELECT * FROM stg_hotel_categories ON CONFLICT (category_code)  DO NOTHING;
INSERT INTO oltp.hotels           SELECT * FROM stg_hotels           ON CONFLICT (hotel_code)     DO NOTHING;
INSERT INTO oltp.room_types       SELECT * FROM stg_room_types       ON CONFLICT (room_type_code) DO NOTHING;
INSERT INTO oltp.rooms            SELECT * FROM stg_rooms            ON CONFLICT (room_id)        DO NOTHING;
INSERT INTO oltp.booking_statuses SELECT * FROM stg_booking_statuses ON CONFLICT (status_code)   DO NOTHING;
INSERT INTO oltp.guests           SELECT * FROM stg_guests           ON CONFLICT (guest_code)     DO NOTHING;
INSERT INTO oltp.bookings         SELECT * FROM stg_bookings         ON CONFLICT (booking_code)   DO NOTHING;
INSERT INTO oltp.payments         SELECT * FROM stg_payments         ON CONFLICT (payment_code)   DO NOTHING;

DO $$
BEGIN
    RAISE NOTICE 'Load complete.';
    RAISE NOTICE 'countries:        %', (SELECT COUNT(*) FROM oltp.countries);
    RAISE NOTICE 'cities:           %', (SELECT COUNT(*) FROM oltp.cities);
    RAISE NOTICE 'hotel_categories: %', (SELECT COUNT(*) FROM oltp.hotel_categories);
    RAISE NOTICE 'hotels:           %', (SELECT COUNT(*) FROM oltp.hotels);
    RAISE NOTICE 'room_types:       %', (SELECT COUNT(*) FROM oltp.room_types);
    RAISE NOTICE 'rooms:            %', (SELECT COUNT(*) FROM oltp.rooms);
    RAISE NOTICE 'booking_statuses: %', (SELECT COUNT(*) FROM oltp.booking_statuses);
    RAISE NOTICE 'guests:           %', (SELECT COUNT(*) FROM oltp.guests);
    RAISE NOTICE 'bookings:         %', (SELECT COUNT(*) FROM oltp.bookings);
    RAISE NOTICE 'payments:         %', (SELECT COUNT(*) FROM oltp.payments);
END $$;
