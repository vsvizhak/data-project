-- V2__create_core_tables.sql
CREATE TABLE drivers (
    id              SERIAL PRIMARY KEY,
    first_name      VARCHAR(50)  NOT NULL,
    last_name       VARCHAR(50)  NOT NULL,
    license_number  VARCHAR(20)  NOT NULL UNIQUE,
    car_model       VARCHAR(100),
    car_year        SMALLINT,
    rating          NUMERIC(3,2) DEFAULT 5.00,
    status          VARCHAR(20)  NOT NULL DEFAULT 'offline',
    current_zone_id INTEGER REFERENCES zones(id),
    created_at      TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
    CONSTRAINT chk_driver_status CHECK (status IN ('online', 'offline', 'on_ride')),
    CONSTRAINT chk_driver_rating CHECK (rating BETWEEN 1.00 AND 5.00)
);

CREATE TABLE customers (
    id              SERIAL PRIMARY KEY,
    first_name      VARCHAR(50)  NOT NULL,
    last_name       VARCHAR(50)  NOT NULL,
    email           VARCHAR(100) NOT NULL UNIQUE,
    phone           VARCHAR(20),
    rating          NUMERIC(3,2) DEFAULT 5.00,
    created_at      TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
    CONSTRAINT chk_customer_rating CHECK (rating BETWEEN 1.00 AND 5.00)
);

CREATE TABLE rides (
    id                  SERIAL PRIMARY KEY,
    customer_id         INTEGER      NOT NULL REFERENCES customers(id),
    driver_id           INTEGER      REFERENCES drivers(id),
    pickup_zone_id      INTEGER      NOT NULL REFERENCES zones(id),
    dropoff_zone_id     INTEGER      NOT NULL REFERENCES zones(id),
    status              VARCHAR(20)  NOT NULL DEFAULT 'requested',
    base_price          NUMERIC(8,2),
    surge_multiplier    NUMERIC(4,2) DEFAULT 1.00,
    final_price         NUMERIC(8,2),
    passenger_count     SMALLINT     DEFAULT 1,
    payment_type        VARCHAR(20),
    requested_at        TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
    accepted_at         TIMESTAMPTZ,
    started_at          TIMESTAMPTZ,
    completed_at        TIMESTAMPTZ,
    cancelled_at        TIMESTAMPTZ,
    CONSTRAINT chk_ride_status CHECK (status IN (
        'requested', 'accepted', 'started', 'completed', 'cancelled'
    )),
    CONSTRAINT chk_payment_type CHECK (payment_type IN (
        'credit_card', 'cash', 'app_wallet', NULL
    ))
);

CREATE TABLE ride_events (
    id          SERIAL PRIMARY KEY,
    ride_id     INTEGER     NOT NULL REFERENCES rides(id),
    event_type  VARCHAR(20) NOT NULL,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    metadata    JSONB,
    CONSTRAINT chk_event_type CHECK (event_type IN (
        'requested', 'accepted', 'started', 'completed', 'cancelled'
    ))
);

CREATE TABLE weather_snapshots (
    id              SERIAL PRIMARY KEY,
    zone_id         INTEGER      NOT NULL REFERENCES zones(id),
    temperature_c   NUMERIC(5,2),
    precipitation   NUMERIC(5,2),
    wind_speed_kmh  NUMERIC(5,2),
    condition       VARCHAR(50),
    recorded_at     TIMESTAMPTZ  NOT NULL DEFAULT NOW()
);

-- Indexes for common query patterns
CREATE INDEX idx_rides_customer_id     ON rides(customer_id);
CREATE INDEX idx_rides_driver_id       ON rides(driver_id);
CREATE INDEX idx_rides_pickup_zone     ON rides(pickup_zone_id);
CREATE INDEX idx_rides_status          ON rides(status);
CREATE INDEX idx_rides_requested_at    ON rides(requested_at);
CREATE INDEX idx_ride_events_ride_id   ON ride_events(ride_id);
CREATE INDEX idx_drivers_zone          ON drivers(current_zone_id);
CREATE INDEX idx_drivers_status        ON drivers(status);
CREATE INDEX idx_weather_zone_time     ON weather_snapshots(zone_id, recorded_at);