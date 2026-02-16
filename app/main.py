from fastapi import FastAPI
import os

app = FastAPI()

@app.get("/")
def read_root():
    return {
        "message": "TEST",
        "hostname": os.uname().nodename
    }
