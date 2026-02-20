from fastapi import FastAPI
import os

app = FastAPI()

@app.get("/")
def read_root():
    return {
        "message": "spark",
        "hostname": os.uname().nodename
    }
