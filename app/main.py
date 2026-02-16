from fastapi import FastAPI
import os

app = FastAPI()

@app.get("/")
def read_root():
    return {
        "message": "TEST2",
        "hostname": os.uname().nodename
    }
