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

- Reception: control room status (including when a room is available to online guests), create reservations, review and confirm online transfer requests, extend active stays, check guests out, and update payments.
- Manager: maintain the hotel's identity, street address, Nigerian city/state, and its separate Director/Reception accounts; register and edit hotel-owned rooms; manage one to three guest-facing room photos and descriptions, bank transfer instructions, and Reception contacts; review the booking calendar; and edit or cancel bookings while retaining payment history.
- Director: review the same operational data with revenue and payment visibility.

Supabase is the production data backend when `SUPABASE_URL`, `SUPABASE_ANON_KEY`, and server-only `SUPABASE_SECRET_KEY` are configured. The secret key is used only by Flask for Manager-managed Auth users; passwords are stored by Supabase Auth, never in public tables. Without those variables, local development falls back to SQLite at `instance/booking_os.sqlite3`.

Existing SQLite databases are cleaned once at startup: the known sample booking and unbooked sample-room records are removed, while rooms with reservation or payment history are retained.

## Supabase Setup

1. Ensure the project's existing base schema has been applied. If it was initialized with the sample-room seed, run `supabase_remove_demo_data.sql` now, before enabling multi-hotel onboarding; it removes only matching rooms with no reservation or payment history.
2. Run `supabase_online_booking_migration.sql` to add online listings/settings, the 30-minute pending-payment status, booking RPCs, and the public room-photo bucket.
3. Run `supabase_multihotel_migration.sql` once. It migrates existing Labim records into the Labim tenant, adds tenant-scoped room, reservation, payment, profile, and online settings, and updates RLS policies.
4. Run `supabase_hotel_location_migration.sql` to add the address, city, and Nigerian state fields for existing hotel records.
5. Run `supabase_reception_email_migration.sql` to add a per-hotel Reception notification email. In the hosting service's environment variables, configure `SMTP_HOST`, `SMTP_PORT`, `SMTP_FROM_EMAIL`, `SMTP_USERNAME`, and `SMTP_PASSWORD` using credentials from your email provider. Port 465 uses implicit TLS; other ports use STARTTLS. Keep credentials private and out of source control.
6. Run `supabase_reception_room_availability_migration.sql` to add support for up to three room photos and require Reception-marked available rooms in the online booking RPC.
7. Run `supabase_reservation_overlap_guard_migration.sql` to serialize reservation writes per room and reject overlapping active stays, including Reception bookings, online requests, edits, extensions, and confirmations.
8. Run `supabase_hotel_subscriptions_migration.sql` before deploying subscription-enabled code. Existing hotels are backfilled as grandfathered (`legacy`) and retain access. New registrations can start a 30-day trial or select monthly (₦80,000 / 30 days) or annual (₦800,000 / 365 days) access. Trials and paid access are not automatically renewed. When a trial or paid term expires, the hotel is hidden from the public booking directory and new online booking submissions are rejected until renewal; existing reservations are retained.
9. In Manager **Hotel and Team**, enter the hotel's Nigerian street address, city, and state/FCT. In **Online Booking Setup**, save the bank details, Reception WhatsApp number, and Reception notification email. Managers upload one to three room photos and maintain guest-facing descriptions. Reception controls room status; only rooms marked **Available** and free on the selected dates are shown to guests.
10. Deploy the service. The Rooms homepage at `/` links guests to hotels and house rentals. The Hotel Manager, Director, and Reception portal is at `/book.admin`; use **Hotel Manager? Register your hotel** there to create a hotel and its team accounts. Hotel staff access is isolated by hotel. Guests can filter the `/book` hotel directory by Nigerian state/FCT, city, stay dates, and room price per night (₦10,000–₦50,000, above ₦50,000–₦100,000, above ₦100,000–₦200,000, or above ₦200,000); results include hotels with listed, Reception-available rooms in that band for those dates. The selected hotel's room list retains the price filter. Guests can also use a hotel's dedicated booking link from Manager **Online Booking Setup**. New guest requests send an email notification to the configured Reception email; Reception still signs into **Online Requests**, verifies payment, and confirms the booking in the app.

The public Data API must expose the `hotels`, `profiles`, `rooms`, `reservations`, `payments`, `online_room_listings`, `online_booking_settings`, `hotel_subscriptions`, and `hotel_subscription_payments` tables. The schema grants authenticated users hotel- and role-scoped access through RLS; subscription tables have no client policies and are managed server-side only. All role values used by policies are assigned in Supabase Auth `app_metadata` by the server-side Manager account workflow. The service-only Supabase secret must be configured because it powers guest booking, transfer verification, subscription billing, and room-image storage.

## Deploy to Render

The root `render.yaml` Blueprint builds the Flutter PWA and Flask service from
the root `Dockerfile`, checks `/health`, and mounts a persistent disk at
`/app/instance` for SQLite fallback data and locally stored room photos.

1. In Render, create a **Blueprint** from this GitHub repository and select the
   branch containing `render.yaml`. The service needs a paid plan for its
   persistent disk.
2. When prompted, copy the current `SUPABASE_URL`, `SUPABASE_ANON_KEY`,
   `SUPABASE_SECRET_KEY`, `PAYSTACK_SECRET_KEY`, `SMTP_HOST`, `SMTP_PORT`,
   `SMTP_FROM_EMAIL`, `SMTP_USERNAME`, and `SMTP_PASSWORD` values from the
   existing host into Render's private environment variables. Never paste
   secret values into chat or commit them. Render generates `FLASK_SECRET_KEY`.
3. On an existing database, ensure the base schema and online-booking migration
   have been applied, then run `supabase_multihotel_migration.sql`,
   `supabase_hotel_location_migration.sql`,
   `supabase_reception_email_migration.sql`,
   `supabase_reception_room_availability_migration.sql`,
   `supabase_reservation_overlap_guard_migration.sql`, and
   `supabase_hotel_subscriptions_migration.sql` in Supabase before deploying.
   Do not use an empty local `supabase_schema.sql` as a schema migration.
4. Verify `/health`, `/book`, hotel search, a test booking, manager/reception
   login, and Paystack subscription checkout on Render. Update the Paystack
   webhook URL to `https://<your-render-domain>/billing/paystack/webhook`.
5. After verifying production behavior, point your custom domain at Render (if
   you have one) and update links in any external rooms app. The Railway
   generated `railway.app` hostname cannot be reused on Render. Keep Railway
   available until Render has passed verification; then disable its service to
   avoid duplicate production instances.
6. After deployment, Managers must save a valid Reception notification email
   under **Online Booking Setup**. Existing hotels need to save their
   notification email once after the migration.

Supabase remains the production database, so deploying to Render does not move
or reset hotel records. The persistent disk is for the SQLite fallback and
local files; keep it attached if either is used. The older `railway.json` is
retained temporarily for rollback.

## Flutter guest booking web app

The Flutter Rooms homepage is served at `/`, the house-rental preview is at
`/rental`, and the Hotel Manager, Director, and Reception portal is available
at `/book.admin`. The rental page is a mockup with clearly labeled sample
listings and a simulated inspection-choice flow; it does not read rental data,
send requests, or collect payments. The separate rental admin and Supabase
integration will be connected later. The server-rendered guest
booking flow at `/book` matches the intended hotel
directory, date/price search, room selection, guest details, and payment
handoff. It uses the same origin as Flask and submits directly into the existing
reservation and Reception-notification workflow. A rooms app can link to
`/book?hotel=<slug>`. `/book-legacy` remains an alias for this flow. The Flutter
guest booking PWA is available separately at `/book-app`; see
`hotel_booking_web_app/README.md` for local development details.
