# HAIDWARE Hotel Booking PWA

Flutter Web guest booking PWA for the Labim Booking OS. Hotel, room, nightly rate,
availability, and payment-instruction data is retrieved from the Flask service;
this app contains no seeded hotel or room records.

In production, the app is served by Flask at `/book` on the active host.
Installable PWA launches open `/book`; `?hotel=<slug>` can be added to link
directly to a hotel. The PWA uses the current page's origin for the backend by
default, so the Render service URL does not need to be compiled into the app.

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
URL, optionally including `?hotel=<slug>`.
