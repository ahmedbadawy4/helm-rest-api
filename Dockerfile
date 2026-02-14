# syntax=docker/dockerfile:1

FROM python:3.12-slim AS runtime

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    LISTEN_HOST=0.0.0.0 \
    LISTEN_PORT=8080

WORKDIR /app

RUN apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates \
    && rm -rf /var/lib/apt/lists/*

RUN groupadd -r -g 10001 appuser \
    && useradd -r -u 10001 -g 10001 -s /usr/sbin/nologin -M appuser

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY app/ ./app/

EXPOSE 8080

USER 10001:10001

CMD ["sh", "-c", "python -m uvicorn app.main:app --host \"$LISTEN_HOST\" --port \"$LISTEN_PORT\""]
