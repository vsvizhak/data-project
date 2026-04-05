"""
seed.py
Downloads NYC TLC Yellow Taxi data (3 months) and seeds the database.
Generates synthetic drivers and customers via Faker.
"""
import os
import io
import logging
import requests
import pandas as pd
import psycopg2
from psycopg2.extras import execute_values
from faker import Faker

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

# NYC TLC Yellow Taxi Parquet files (3 months of 2024)
TLC_URLS = [
    "https://d37ci6vzurychx.cloudfront.net/trip-data/yellow_tripdata_2024-01.parquet",
    "https://d37ci6vzurychx.cloudfront.net/trip-data/yellow_tripdata_2024-02.parquet",
    "https://d37ci6vzurychx.cloudfront.net/trip-data/yellow_tripdata_2024-03.parquet",
]

PAYMENT_TYPE_MAP = {1: "credit_card", 2: "cash", 3: "app_wallet", 4: "app_wallet"}

CAR_MODELS = [
    "Toyota Camry", "Toyota Prius", "Honda Accord", "Ford Fusion",
    "Chevrolet Malibu", "Nissan Altima", "Hyundai Sonata", "Kia Optima",
]


def get_conn():
    return psycopg2.connect(**DB)


def already_seeded(conn) -> bool:
    with conn.cursor() as cur:
        cur.execute("SELECT COUNT(*) FROM rides")
        count = cur.fetchone()[0]
    return count > 0


def seed_drivers(conn, n: int = 500) -> list[int]:
    log.info(f"Generating {n} drivers...")
    rows = []
    for _ in range(n):
        rows.append((
            fake.first_name(),
            fake.last_name(),
            fake.bothify("TLC-#####??").upper(),
            fake.random_element(CAR_MODELS),
            fake.random_int(2015, 2024),
            round(fake.random.uniform(3.5, 5.0), 2),
            "offline",
        ))
    with conn.cursor() as cur:
        execute_values(cur, """
            INSERT INTO drivers
                (first_name, last_name, license_number, car_model, car_year, rating, status)
            VALUES %s
            ON CONFLICT (license_number) DO NOTHING
            RETURNING id
        """, rows)
        ids = [r[0] for r in cur.fetchall()]
    conn.commit()
    log.info(f"Inserted {len(ids)} drivers")
    return ids


def seed_customers(conn, n: int = 5000) -> list[int]:
    log.info(f"Generating {n} customers...")
    rows = []
    for _ in range(n):
        rows.append((
            fake.first_name(),
            fake.last_name(),
            fake.unique.email(),
            fake.numerify("###-###-####"),
            round(fake.random.uniform(3.5, 5.0), 2),
        ))
    with conn.cursor() as cur:
        execute_values(cur, """
            INSERT INTO customers (first_name, last_name, email, phone, rating)
            VALUES %s
            ON CONFLICT (email) DO NOTHING
            RETURNING id
        """, rows)
        ids = [r[0] for r in cur.fetchall()]
    conn.commit()
    log.info(f"Inserted {len(ids)} customers")
    return ids


def download_parquet(url: str) -> pd.DataFrame:
    log.info(f"Downloading {url}...")
    r = requests.get(url, timeout=120)
    r.raise_for_status()
    df = pd.read_parquet(io.BytesIO(r.content))
    log.info(f"Downloaded {len(df):,} rows")
    return df


def clean_tlc(df: pd.DataFrame) -> pd.DataFrame:
    df = df[[
        "PULocationID", "DOLocationID", "passenger_count",
        "fare_amount", "tip_amount", "payment_type",
        "tpep_pickup_datetime", "tpep_dropoff_datetime",
    ]].copy()

    df = df.dropna(subset=["PULocationID", "DOLocationID", "tpep_pickup_datetime"])
    df = df[df["PULocationID"].between(1, 265)]
    df = df[df["DOLocationID"].between(1, 265)]
    df = df[df["fare_amount"] > 0]
    df["passenger_count"] = df["passenger_count"].fillna(1).clip(1, 6).astype(int)
    df["payment_type"] = df["payment_type"].map(PAYMENT_TYPE_MAP).fillna("cash")
    df["PULocationID"] = df["PULocationID"].astype(int)
    df["DOLocationID"] = df["DOLocationID"].astype(int)

    return df


def seed_rides(conn, df: pd.DataFrame, driver_ids: list, customer_ids: list):
    import random
    log.info(f"Inserting {len(df):,} rides...")

    rows = []
    for _, row in df.iterrows():
        base = float(row["fare_amount"])
        tip  = float(row["tip_amount"]) if pd.notna(row["tip_amount"]) else 0
        surge = round(random.uniform(1.0, 1.5), 2)

        rows.append((
            random.choice(customer_ids),
            random.choice(driver_ids),
            int(row["PULocationID"]),
            int(row["DOLocationID"]),
            "completed",
            round(base, 2),
            surge,
            round(base * surge + tip, 2),
            int(row["passenger_count"]),
            row["payment_type"],
            row["tpep_pickup_datetime"],
            row["tpep_pickup_datetime"],  # accepted_at ≈ pickup
            row["tpep_pickup_datetime"],  # started_at  ≈ pickup
            row["tpep_dropoff_datetime"], # completed_at
        ))

    chunk_size = 5000
    with conn.cursor() as cur:
        for i in range(0, len(rows), chunk_size):
            execute_values(cur, """
                INSERT INTO rides (
                    customer_id, driver_id,
                    pickup_zone_id, dropoff_zone_id,
                    status, base_price, surge_multiplier, final_price,
                    passenger_count, payment_type,
                    requested_at, accepted_at, started_at, completed_at
                ) VALUES %s
            """, rows[i:i + chunk_size])
            conn.commit()
            log.info(f"  inserted {min(i + chunk_size, len(rows)):,} / {len(rows):,}")

    log.info("Rides inserted.")


def main():
    conn = get_conn()

    if already_seeded(conn):
        log.info("Database already seeded — skipping.")
        conn.close()
        return

    driver_ids   = seed_drivers(conn)
    customer_ids = seed_customers(conn)

    for url in TLC_URLS:
        df = download_parquet(url)
        df = clean_tlc(df)
        seed_rides(conn, df, driver_ids, customer_ids)

    conn.close()
    log.info("Seeding complete!")


if __name__ == "__main__":
    main()