FROM python:3.11-slim

WORKDIR /app

RUN pip install --no-cache-dir dbt-core dbt-trino

COPY . /app

CMD ["dbt", "--version"]
