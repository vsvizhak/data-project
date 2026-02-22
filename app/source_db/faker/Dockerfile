FROM python:3.12-slim

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY seed.py .
COPY faker.py .

CMD ["sh", "-c", "python seed.py && python faker.py"]