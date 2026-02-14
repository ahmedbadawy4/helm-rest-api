import os

from fastapi import FastAPI

app = FastAPI(title="helm-rest-api")


@app.get("/health")
def health() -> dict:
    return {"status": "ok"}


@app.get("/")
def root() -> dict:
    return {
        "service": "helm-rest-api",
        "listen_host": os.getenv("LISTEN_HOST", ""),
        "listen_port": os.getenv("LISTEN_PORT", ""),
    }
