FROM ghcr.io/cirruslabs/flutter:stable AS flutter-build

WORKDIR /src/hotel_booking_web_app
COPY hotel_booking_web_app/ ./
RUN flutter pub get \
    && flutter build web --release --base-href=/

FROM python:3.11-slim

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1

WORKDIR /app
COPY requirements.txt ./
RUN pip install --no-cache-dir -r requirements.txt
COPY app.py ./
COPY templates/ ./templates/
COPY static/ ./static/
COPY --from=flutter-build /src/hotel_booking_web_app/build/web ./hotel_booking_web_app/build/web/

EXPOSE 10000
CMD ["sh", "-c", "exec gunicorn app:app --bind 0.0.0.0:${PORT:-10000} --threads 4 --timeout 120"]
