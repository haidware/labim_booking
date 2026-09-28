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

The SQLite database is created at `instance/booking_os.sqlite3` on first launch. The Flask route layer intentionally keeps database access in one place so it can later be replaced by Supabase queries and authentication.
