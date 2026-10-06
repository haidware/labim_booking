# Labim Booking OS

A Python Flask operations dashboard and guest booking site for hotel reservations, room status, arrivals and check-outs, and payment tracking. Creating a Reception booking starts the guest's stay and occupies the room; Reception can extend an active stay or check the guest out at departure. Guests can search Manager-published rooms by dates and request an online booking with a 30-minute payment hold. Guests transfer to Manager-configured bank details and open a prefilled WhatsApp message to Reception; Reception verifies each transfer manually and confirms the booking. This WhatsApp contact link is guest-initiated and does not require or send automatic WhatsApp Business API notifications. Managers and Reception can review saved bookings in a weekly calendar and select past or future dates. Business records are read from the configured database; no sample rooms, bookings, or payments are preloaded.

## Run locally

```powershell
python -m venv .venv
.\.venv\Scripts\Activate.ps1
pip install -r requirements.txt
python app.py
```

Open http://127.0.0.1:5000.

## Roles

- Reception: create reservations, review and confirm online transfer requests, extend active stays, check guests out, and update payments.
- Manager: maintain the hotel's identity and its separate Director/Reception accounts; register and edit hotel-owned rooms; manage public room photos and descriptions, bank transfer instructions, and Reception's WhatsApp number; review the booking calendar; and edit or cancel bookings while retaining payment history.
- Director: review the same operational data with revenue and payment visibility.

Supabase is the production data backend when `SUPABASE_URL`, `SUPABASE_ANON_KEY`, and server-only `SUPABASE_SECRET_KEY` are configured. The secret key is used only by Flask for Manager-managed Auth users; passwords are stored by Supabase Auth, never in public tables. Without those variables, local development falls back to SQLite at `instance/booking_os.sqlite3`.

Existing SQLite databases are cleaned once at startup: the known sample booking and unbooked sample-room records are removed, while rooms with reservation or payment history are retained.

## Supabase Setup

1. Ensure the project's existing base schema has been applied. If it was initialized with the sample-room seed, run `supabase_remove_demo_data.sql` now, before enabling multi-hotel onboarding; it removes only matching rooms with no reservation or payment history.
2. Run `supabase_online_booking_migration.sql` to add online listings/settings, the 30-minute pending-payment status, booking RPCs, and the public room-photo bucket.
3. Run `supabase_multihotel_migration.sql` once. It migrates existing Labim records into the Labim tenant, adds tenant-scoped room, reservation, payment, profile, and online settings, and updates RLS policies. The Manager publishes rooms from **Online Booking Setup** after uploading a room photo and saving bank/WhatsApp details.
4. In Railway service variables, set `SUPABASE_URL`, `SUPABASE_ANON_KEY` (the publishable key), and `SUPABASE_SECRET_KEY` (the Supabase secret/server key). Do not put the secret key in `.env.example`, source control, or browser code.
5. Deploy the service. Use **Hotel Manager? Register your hotel** to create a hotel and its Manager, Director, and Reception accounts. Hotel staff access is isolated by hotel. Guests can select a hotel at `/book` or use its hotel-specific link from Manager **Online Booking Setup**. Reception verifies transfer requests under **Online Requests** and records a confirmed transfer from that page.

The public Data API must expose the `hotels`, `profiles`, `rooms`, `reservations`, `payments`, `online_room_listings`, and `online_booking_settings` tables. The schema grants authenticated users hotel- and role-scoped access through RLS. All role values used by policies are assigned in Supabase Auth `app_metadata` by the server-side Manager account workflow. The service-only Supabase secret must be configured because it powers guest booking, transfer verification, and room-image storage.

## Deploy to Railway

1. Create a Railway project and deploy this GitHub repository.
2. Set `FLASK_SECRET_KEY` to a long random value in the Railway service variables.
3. Set Supabase variables as described above. On an existing database, ensure the base schema and online-booking migration have been applied, then run `supabase_multihotel_migration.sql` once in the Supabase SQL Editor before deploying the multi-hotel application. Do not use an empty local `supabase_schema.sql` as a schema migration.
4. Deploy with the included Railway config and Procfile; Gunicorn serves the Flask app and `/health` is the health endpoint.

SQLite remains a local fallback. The current Railway volume is mounted at `/app/instance` for that fallback only.
