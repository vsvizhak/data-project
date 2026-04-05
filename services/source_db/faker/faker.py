"""
faker_producer.py
Continuously inserts new ride requests to simulate live taxi activity.
Runs indefinitely after seed.py completes.
"""
import os
import time
import random
import logging
import psycopg2
from psycopg2.extras import execute_values
from faker import Faker
from datetime import datetime, timezone

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")
log = logging.getLogger(__name__)

fake = Faker()

DB = {
    "host":     os.environ["DB_HOST"],
    "port":     os.environ.get("DB_PORT", "5432"),
    "dbname":   os.environ["DB_NAME"],
    "user":     os.environ["DB_USER"],
    "password": os.environ["DB_PASSWORD"],
}

# How many new rides to insert per batch and how often
BATCH_SIZE    = int(os.environ.get("FAKER_BATCH_SIZE", "10"))
INTERVAL_SEC  = int(os.environ.get("FAKER_INTERVAL_SEC", "30"))

# Manhattan zones — higher weight to make it realistic
MANHATTAN_ZONES = list(range(4, 265))


def get_conn():
    return psycopg2.connect(**DB)


def get_ids(conn, table: str, id_col: str = "id") -> list[int]:
    with conn.cursor() as cur:
        cur.execute(f"SELECT {id_col} FROM {table}")
        return [r[0] for r in cur.fetchall()]


def insert_rides(conn, driver_ids, customer_ids, n: int):
    now = datetime.now(timezone.utc)
    rows = []
    for _ in range(n):
        pickup  = random.randint(1, 265)
        dropoff = random.randint(1, 265)
        base    = round(random.uniform(5.0, 60.0), 2)
        surge   = round(random.uniform(1.0, 2.5), 2)

        rows.append((
            random.choice(customer_ids),
            random.choice(driver_ids),
            pickup,
            dropoff,
            "requested",
            base,
            surge,
            round(base * surge, 2),
            random.randint(1, 4),
            random.choice(["credit_card", "cash", "app_wallet"]),
            now,
        ))

    with conn.cursor() as cur:
        execute_values(cur, """
            INSERT INTO rides (
                customer_id, driver_id,
                pickup_zone_id, dropoff_zone_id,
                status, base_price, surge_multiplier, final_price,
                passenger_count, payment_type,
                requested_at
            ) VALUES %s
            RETURNING id
        """, rows)
        ride_ids = [r[0] for r in cur.fetchall()]

        # Insert ride_events for each new ride
        events = [(rid, "requested", now) for rid in ride_ids]
        execute_values(cur, """
            INSERT INTO ride_events (ride_id, event_type, created_at)
            VALUES %s
        """, events)

    conn.commit()
    log.info(f"Inserted {n} new rides (status=requested)")


def main():
    log.info("Faker producer starting...")
    conn = get_conn()

    driver_ids   = get_ids(conn, "drivers")
    customer_ids = get_ids(conn, "customers")
    log.info(f"Loaded {len(driver_ids)} drivers, {len(customer_ids)} customers")

    while True:
        try:
            insert_rides(conn, driver_ids, customer_ids, BATCH_SIZE)
        except Exception as e:
            log.error(f"Error inserting rides: {e}")
            conn = get_conn()  # reconnect on error

        time.sleep(INTERVAL_SEC)


if __name__ == "__main__":
    main()