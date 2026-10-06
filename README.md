# Labim Booking OS

A Python Flask operations dashboard for hotel reservations, room status, guest arrivals and check-outs, and payment tracking. Creating a booking starts the guest's stay and occupies the room; Reception can extend an active stay or check the guest out at departure. Managers and Reception can review saved bookings in a weekly calendar and select past or future dates. Business records are read from the configured database; no sample rooms, bookings, or payments are preloaded.

## Run locally

```powershell
python -m venv .venv
.\.venv\Scripts\Activate.ps1
pip install -r requirements.txt
python app.py
```

Open http://127.0.0.1:5000.

## Roles

- Reception: create reservations, extend active stays, check guests out, and update payments.
- Manager: register and edit room categories, bed counts, and nightly rates; remove rooms without booking history or mark historical rooms unavailable when they have no active booking; review the booking calendar; and edit or cancel bookings while retaining payment history.
- Director: review the same operational data with revenue and payment visibility.

Supabase is the production data backend when `SUPABASE_URL`, `SUPABASE_ANON_KEY`, and server-only `SUPABASE_SECRET_KEY` are configured. The secret key is used only by Flask for Manager-managed Auth users; passwords are stored by Supabase Auth, never in public tables. Without those variables, local development falls back to SQLite at `instance/booking_os.sqlite3`.

Existing SQLite databases are cleaned once at startup: the known sample booking and unbooked sample-room records are removed, while rooms with reservation or payment history are retained.

## Supabase Setup

1. Run `supabase_schema.sql` in the Supabase SQL Editor for the project. It creates an empty room inventory; the Manager registers the property's rooms from the Rooms workspace. Rerun the updated schema after application updates to apply compatible status and RLS policy changes, including Manager deletion of rooms without booking or payment history.
2. If this project was previously initialized with the sample-room seed, run `supabase_remove_demo_data.sql` once. It removes only matching sample rooms with no reservation or payment history.
3. In Railway service variables, set `SUPABASE_URL`, `SUPABASE_ANON_KEY` (the publishable key), and `SUPABASE_SECRET_KEY` (the Supabase secret/server key). Do not put the secret key in `.env.example`, source control, or browser code.
4. Deploy the service. Open Manager Login and use the initial Manager Sign Up flow to create Manager, Director, and Reception Auth accounts.

The public Data API must expose the `profiles`, `rooms`, `reservations`, and `payments` tables. The schema grants authenticated users role-scoped access through RLS. All role values used by policies are assigned in Supabase Auth `app_metadata` by the server-side Manager account workflow.

## Deploy to Railway

1. Create a Railway project and deploy this GitHub repository.
2. Set `FLASK_SECRET_KEY` to a long random value in the Railway service variables.
3. Set Supabase variables as described above, then run `supabase_schema.sql` in the Supabase SQL Editor. For an existing installation with sample rooms, also run `supabase_remove_demo_data.sql` once.
4. Deploy with the included Railway config and Procfile; Gunicorn serves the Flask app and `/health` is the health endpoint.

SQLite remains a local fallback. The current Railway volume is mounted at `/app/instance` for that fallback only.
