# Multi-stage build for production-ready Django & Daphne container

# --- Stage 1: Build dependencies ---
FROM python:3.12-slim AS builder

WORKDIR /app

ENV PYTHONDONTWRITEBYTECODE=1
ENV PYTHONUNBUFFERED=1

RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    libpq-dev \
    && rm -rf /var/lib/apt/lists/*

COPY requirements.txt .
RUN pip install --no-cache-dir --prefix=/install -r requirements.txt

# --- Stage 2: Final Run Image ---
FROM python:3.12-slim

WORKDIR /app

RUN apt-get update && apt-get install -y --no-install-recommends \
    libpq5 \
    curl \
    && rm -rf /var/lib/apt/lists/*

COPY --from=builder /install /usr/local

COPY . .

# Environment Defaults
ENV PORT=8000
ENV PYTHONUNBUFFERED=1
ENV PYTHONDONTWRITEBYTECODE=1

# Expose Django port (both HTTP and WebSockets via Daphne)
EXPOSE 8000

# Script to run migrations and start Daphne ASGI server
CMD ["sh", "-c", "python manage.py migrate --noinput && python manage.py collectstatic --noinput && daphne -b 0.0.0.0 -p $PORT c2_dashboard.asgi:application"]
