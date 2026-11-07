# Labim Booking OS

A Python Flask operations dashboard and guest booking site for hotel reservations, shortlet apartments, room status, arrivals and check-outs, and payment tracking. Creating a Reception booking starts the guest's stay and occupies the room; Reception can extend an active stay or check the guest out at departure. Guests can search Manager-published rooms by dates and request an online booking with a 30-minute payment hold. Shortlet apartments have separate inventory and pricing; guests submit availability requests manually through WhatsApp and do not create an instant booking or payment. After transferring to Manager-configured bank details, hotel guests report the sender account name and number; this report is saved under the hotel for month-end reconciliation and added to a prefilled WhatsApp message. WhatsApp opens the prefilled chat but does not send automatically; the guest must tap **Send** to contact the manager. After returning, the guest sees a waiting page with their booking reference until Reception verifies payment and approves the booking; the receipt is not issued before approval. Guests can opt in to a device push notification for that booking; Reception approval sends a notification linking to the verified receipt. Reception verifies deposits manually and confirms hotel bookings. WhatsApp remains guest-initiated; the app does not send automatic WhatsApp Business API notifications or verify message delivery. Managers and Reception can review saved bookings in a weekly calendar and select past or future dates. Business records are read from the configured database; no sample rooms, bookings, or payments are preloaded.

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
- Manager: maintain the hotel's identity, street address, Nigerian city/state, and its separate Director/Reception accounts; register and edit hotel-owned rooms; manage up to five guest-facing room photos (any number from one to five) and descriptions, bank transfer instructions, and Reception contacts; review the booking calendar; and edit or cancel bookings while retaining payment history.
- Director: review the same operational data with revenue and payment visibility.
- Haidware Controller: use the separate service-level login and Command Center dashboard to issue hotel IDs, review monthly guest payment reports, and manage Apartment shortlet listings. Configure its private Railway variables `HAIDWARE_CONTROLLER_USERNAME` and `HAIDWARE_CONTROLLER_PASSWORD`; these are independent of hotel Director, Manager, and Reception accounts.

Supabase is the production data backend when `SUPABASE_URL`, `SUPABASE_ANON_KEY`, and server-only `SUPABASE_SECRET_KEY` are configured. The secret key is used only by Flask for Manager-managed Auth users; passwords are stored by Supabase Auth, never in public tables. Without those variables, local development falls back to SQLite at `instance/booking_os.sqlite3`.

Existing SQLite databases are cleaned once at startup: the known sample booking and unbooked sample-room records are removed, while rooms with reservation or payment history are retained.

## Supabase Setup

1. Ensure the project's existing base schema has been applied. If it was initialized with the sample-room seed, run `supabase_remove_demo_data.sql` now, before enabling multi-hotel onboarding; it removes only matching rooms with no reservation or payment history.
2. Run `supabase_online_booking_migration.sql` to add online listings/settings, the 30-minute pending-payment status, booking RPCs, and the public room-photo bucket.
3. Run `supabase_multihotel_migration.sql` once. It migrates existing Labim records into the Labim tenant, adds tenant-scoped room, reservation, payment, profile, and online settings, and updates RLS policies.
4. Run `supabase_hotel_location_migration.sql` to add the address, city, and Nigerian state fields for existing hotel records.
5. Run `supabase_reception_email_migration.sql` to add a per-hotel Reception notification email. In the hosting service's environment variables, configure `SMTP_HOST`, `SMTP_PORT`, `SMTP_FROM_EMAIL`, `SMTP_USERNAME`, and `SMTP_PASSWORD` using credentials from your email provider. Port 465 uses implicit TLS; other ports use STARTTLS. Keep credentials private and out of source control.
6. Run `supabase_reception_room_availability_migration.sql` to add support for up to five room photos and require Reception-marked available rooms in the online booking RPC.
7. Run `supabase_reservation_overlap_guard_migration.sql` to serialize reservation writes per room and reject overlapping active stays, including Reception bookings, online requests, edits, extensions, and confirmations.
8. Run `supabase_hotel_number_migration.sql`, then `supabase_hotel_registration_ids_migration.sql` before deploying. The first assigns existing hotels sequential IDs; the second lets the Haidware Controller issue one-time registration IDs from the Command Center. Managers must enter an available ID, such as `HOTEL-0001`, during signup. Issued IDs are linked to a hotel and cannot be reused. Manager signup no longer asks for a subscription plan or billing email. The business model is commission-based, but commission calculations are not implemented yet. Legacy subscription records are retained but no longer control hotel access.
9. Run `supabase_whatsapp_handoff_migration.sql`, then `supabase_payment_report_migration.sql` before deploying payment reporting. On the payment confirmation page, the guest enters the sender bank account name and number. Clicking **Confirm payment on WhatsApp** records the claimed amount and sender details under the hotel in Haidware Command Center, then opens a prefilled WhatsApp message with the same details. Guests must manually tap **Send** in WhatsApp; opening the chat does not deliver the message. When the guest returns to Rooms, the app shows the receipt-waiting page and checks for Reception approval. After Reception confirms the payment, the page changes to a confirmed booking and, if push is configured and the guest has enabled notifications, a push alert with the receipt is sent to registered devices. A report means the guest says the transfer was made; it is not independently bank-verified and the app cannot verify WhatsApp message delivery. At month end, the Controller can choose a month in `/commandcenter`, review each hotel's reports, and download the CSV for reconciliation against bank statements. The Haidware Controller login can issue hotel IDs and view reports and registered hotels across all hotels; Hotel Director accounts do not have access to the Command Center.
10. Run `supabase_push_notifications_migration.sql` to store private, booking-specific device push subscriptions. Configure `VAPID_PUBLIC_KEY`, `VAPID_PRIVATE_KEY`, and `VAPID_SUBJECT` as private app environment variables using a generated VAPID key pair; never commit the private key. On first visit from an iPhone/iPad browser, Rooms shows the Safari Home Screen installation guide first; after the user adds Rooms and opens the installed app, notification settings are offered. On Android, notification settings are offered first and then the Home Screen guide. The browser permission dialog is requested only after the guest taps **Allow notifications**. Guests can enable or retry notification enrollment from the booking's receipt-waiting page; if Reception already approved it, a successful enrollment immediately sends the approval alert to that device. The Home Screen guide's **Got it** choice is remembered in that browser. Android users should open the link in Google Chrome, tap the menu, then **Install app** or **Add to Home screen** and confirm. When Reception approves payment, each registered device receives a push notification linking to the signed receipt. Lock-screen visibility, sound, and vibration depend on device/browser support and notification settings.
11. Run `supabase_room_video_migration.sql` to add room videos to the public media bucket (it allows MP4 and MOV), `supabase_room_mov_video_migration.sql` to update an existing bucket for QuickTime MOV uploads, and `supabase_hotel_profile_migration.sql` to add hotel descriptions and photos. If Supabase reports that `video/quicktime` is not supported, rerun `supabase_room_mov_video_migration.sql` in the Rooms project's Supabase SQL Editor; running the base room-video migration now also preserves the MOV MIME type. In Manager **Hotel and Team**, enter the hotel's Nigerian street address, city, and state/FCT. In **Online Booking Setup**, save the bank details, Reception WhatsApp number, and Reception notification email, plus the guest-facing hotel description and up to five hotel photos (5 MB each). These are shown on the homepage hotel card before guests open its room list. Managers can also upload up to five JPG/PNG/WebP photos per room (5 MB each) and one MP4 or MOV video (up to 3 minutes and 100 MB), and maintain room descriptions. Production room videos upload directly to Supabase using 6 MB resumable chunks, with progress and automatic retries, avoiding Railway's request timeout and restarting less data after connection interruptions. Video playback depends on the guest's browser supporting the video's codec. Uploading a new photo set replaces photos of that type. Guests can browse hotel photos, then swipe through each available room's photos and video. Reception controls room status; only rooms marked **Available** and free on the selected dates are shown to guests.
12. Run `supabase_shortlet_migration.sql` in the Rooms project's Supabase SQL Editor to create the separate shortlet inventory table before using Apartment Admin. This migration belongs to the Rooms Supabase project, not the separate House Rental project's Supabase project.
13. Run `supabase_shortlet_video_migration.sql` in the Rooms Supabase project to enable MP4/MOV video uploads for shortlet listings. Existing shortlet installs need this migration to add the video path and public media bucket; new installs may run it after the base shortlet migration as well.
14. Deploy the service. The hotel search and booking experience is the Rooms homepage at `/`; its **Hotels** tab is selected by default. **Apartments** is the shortlet search; its controller-managed listings are administered at `/commandcenter/apartments` using the existing superuser login. Guests filter shortlets by Nigerian state/FCT, city, stay dates, and nightly price, then enter their name and phone to open a prefilled WhatsApp availability request. The guest must tap **Send** and wait for the manager to confirm availability and price; no booking or payment is created. **Homes** and **Land/Properties** open the separate long-term rental marketplace through same-origin routes `/rentals` and `/rentals/land`, keeping installed mobile Rooms users in the standalone app. The Rooms service proxies those routes and their APIs/assets to `RENTAL_SERVICE_URL` (default `https://labimhouserental-production.up.railway.app`). The rental marketplace is hosted on Railway and continues to use its own Supabase project. The old `/book` URL redirects to `/` and is no longer a separate booking page. The Hotel Manager, Director, and Reception portal is at `/book.admin`; use **Hotel Manager? Register your hotel** there to create a hotel and its team accounts. Hotel staff access is isolated by hotel. Guests can filter hotels by Nigerian state/FCT, city, stay dates, and room price per night (₦10,000–₦50,000, above ₦50,000–₦100,000, above ₦100,000–₦200,000, or above ₦200,000); results include hotels with listed, Reception-available rooms in that band for those dates. The selected hotel's room list retains the price filter. Managers can share a hotel's dedicated homepage link from **Online Booking Setup**. New hotel guest requests send an email notification to the configured Reception email; Reception still signs into **Online Requests**, verifies payment against the bank, and confirms the booking in the app.

The public Data API must expose the `hotels`, `profiles`, `rooms`, `reservations`, `payments`, `online_room_listings`, `online_booking_settings`, `hotel_registration_codes`, `whatsapp_handoff_events`, `web_push_subscriptions`, and `shortlet_listings` tables. The schema grants authenticated users hotel- and role-scoped access through RLS; registration codes, WhatsApp handoff events, push subscriptions, and shortlet listing writes are managed server-side only. Published shortlets are publicly readable. All role values used by policies are assigned in Supabase Auth `app_metadata` by the server-side Manager account workflow. The service-only Supabase secret must be configured because it powers guest booking, transfer verification, hotel registration, push delivery, room-image storage, and shortlet administration.

## Deploy to Railway

The production Railway service is `labim_booking` on the `main` branch:
<https://labimbooking-production.up.railway.app>. The root `Dockerfile` builds
the Flutter PWA and Flask service, and `railway.json` configures `/health` as
the health check.

Configure these private service variables in Railway:
`FLASK_SECRET_KEY`, `SUPABASE_URL`, `SUPABASE_ANON_KEY`, `SUPABASE_SECRET_KEY`,
`HAIDWARE_CONTROLLER_USERNAME`, `HAIDWARE_CONTROLLER_PASSWORD`,
`SMTP_HOST`, `SMTP_PORT`, `SMTP_FROM_EMAIL`, `SMTP_USERNAME`, `SMTP_PASSWORD`,
`VAPID_PUBLIC_KEY`, `VAPID_PRIVATE_KEY`, and `VAPID_SUBJECT`. Never paste secret values into chat or
commit them. The rental proxy uses the Railway rental service by default.

Supabase remains the production database and room-photo store. Deploying to
Railway does not move or reset hotel records; no Railway database is required.
The current service does not have a persistent volume. This is safe while
Supabase is enabled; if the app is switched to its local SQLite fallback or
local photo storage, attach a Railway volume at `/app/instance` first.

Before retiring the old Render service, verify `/health`, `/`, hotel search,
manager/reception login, and a test booking. Keep Render available as a
rollback until these checks pass.

## Flutter guest booking web app

The hotel search and booking experience is served at `/`, with the **Hotels**
tab selected first. **Apartment** opens the short-stay preview at `/apartment`,
**Homes** opens the house-rental preview at `/rental`, and **Land/Properties**
opens the land preview at `/land-properties`. The apartment and land/property
pages show clearly labeled sample listings only; they do not yet connect to
live inventory or accept enquiries. The old `/book` URL redirects to `/`;
hotel-specific links use `/?hotel=<slug>`. The hotel flow includes date and price search, room selection,
guest details, and payment handoff, submitting into the existing reservation
and Reception-notification workflow. `/book-app` remains an alias for the
Flutter hotel booking experience, and `/book-legacy` remains available for the
older server-rendered booking flow. The Hotel Manager, Director, and Reception
portal is at `/book.admin`. The Homes page remains a mockup with sample
listings and a simulated inspection-choice flow; it does not read rental data,
send requests, or collect payments. The separate rental admin and Supabase
integration will be connected later. See `hotel_booking_web_app/README.md` for
local Flutter development details.
