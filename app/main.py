import os

from fastapi import FastAPI
from fastapi.responses import PlainTextResponse
from prometheus_client import CONTENT_TYPE_LATEST, generate_latest

app = FastAPI(title="helm-rest-api")


@app.get("/health")
def health() -> dict:
    return {"status": "ok"}


@app.get("/")
def root() -> dict:
    return {
        "service": "helm-rest-api",
        "environment": os.getenv("APP_ENV", ""),
        "image_tag": os.getenv("APP_IMAGE_TAG", ""),
        "listen_host": os.getenv("LISTEN_HOST", ""),
        "listen_port": os.getenv("LISTEN_PORT", ""),
    }


@app.get("/metrics")
def metrics() -> PlainTextResponse:
    return PlainTextResponse(generate_latest(), media_type=CONTENT_TYPE_LATEST)
