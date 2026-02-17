from fastapi import FastAPI
import os

app = FastAPI()

@app.get("/")
def read_root():
    return {
        "message": "airflow",
        "hostname": os.uname().nodename
    }
