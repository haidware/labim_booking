# Labim Booking OS

A Python Flask operations dashboard for hotel reservations, room status, check-in/check-out, and payment tracking. It mirrors the role flow of the reference site while keeping persistence local until Supabase is connected.

## Run locally

```powershell
python -m venv .venv
.\.venv\Scripts\Activate.ps1
pip install -r requirements.txt
python app.py
```

Open http://127.0.0.1:5000.

## Roles

- Reception: create and manage reservations, check guests in/out, and update payments.
- Manager: monitor room operations and reservation activity.
- Director: review the same operational data with revenue and payment visibility.

The SQLite database is created at `instance/booking_os.sqlite3` on first launch. Supabase client configuration is read from environment variables; business data operations still use SQLite until the Supabase schema and credentials are fully configured.

## Deploy to Railway

1. Create a Railway project and deploy this GitHub repository.
2. Set `FLASK_SECRET_KEY` to a long random value in the Railway service variables.
3. Set `SUPABASE_URL`, `SUPABASE_ANON_KEY`, and the server-only `SUPABASE_SECRET_KEY` when enabling Supabase. Never use the secret key in browser code or commit it.
4. Deploy with the included `railway.json`; Railway builds from `requirements.txt`, starts Gunicorn, and checks `/health`.
5. Until Supabase data operations are enabled, attach a Railway volume mounted at `/app/instance` to persist SQLite across deployments.

Reservation, room, and account operations still use SQLite; Supabase persistence is not active merely by setting the project URL and keys. Railway's container filesystem is ephemeral, so the volume is required to retain local database writes across deployments.
