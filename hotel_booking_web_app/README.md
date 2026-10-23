# HAIDWARE Hotel Booking PWA

Flutter Web guest booking PWA for the Labim Booking OS. Hotel, room, nightly rate,
availability, and payment-instruction data is retrieved from the Flask service;
this app contains no seeded hotel or room records.

In production, this Flutter app serves the Rooms homepage at `/` and the guest
booking PWA at `/book-app`. The server-rendered guest booking experience is at
`/book`, the rental preview is at `/rental`, and the hotel staff portal is at
`/book.admin`. Installable PWA
launches open `/`; guests can open `/book-app` for the dedicated Flutter
booking screen. Add `?hotel=<slug>` to link directly to a hotel. The PWA uses
the current page's origin for the backend by default, so the Render service URL
does not need to be compiled into the app.

The `/rental` route is currently a mockup with clearly labeled sample
properties and a simulated inspection-choice flow. It does not connect to
rental data, send WhatsApp messages, or collect rent or fees. The separate
house-rental admin and Supabase integration will be connected in a later step.

## Local development

From this directory:

```powershell
flutter pub get
flutter run -d chrome --dart-define=API_BASE_URL=http://127.0.0.1:5000
```

Start the Flask app from the repository root before launching Flutter. The local
Flutter origin is allowed by the public booking API's CORS policy.

To point the app at another deployment:

```powershell
flutter run -d chrome --dart-define=API_BASE_URL=https://your-booking-service.example
```

## Guest flow

1. Search active hotels by stay dates, Nigerian state/FCT, city, and nightly
   price range.
2. Open a hotel and select a room that is available for those exact dates.
3. Submit guest details. The server rechecks availability and subscription
   status, creates the existing 30-minute pending-transfer hold, and notifies
   Reception.
4. Show the guest the configured bank-transfer details and the WhatsApp handoff
   to Reception. Reception continues to verify transfer and confirm the booking.

Expired or inactive hotels are excluded by the backend and cannot accept new
booking requests. The app accepts an optional `?hotel=<slug>` parameter so a
rooms-management app can link directly to a particular hotel's guest page.

## Public API

- `GET /api/public/config`
- `GET /api/public/hotels`
- `GET /api/public/hotels/<slug>/rooms`
- `POST /api/public/bookings`

The API is served by the Flask app in the parent repository. Render builds the
Flutter web assets and packages them with Flask using the repository-root
`Dockerfile`. Configure the rooms app's Hotel button with the deployed `/book`
URL to use the reference booking experience, or `/book-app` to open the Flutter
PWA.
