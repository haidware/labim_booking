# HAIDWARE Hotel Booking PWA

Flutter Web guest booking PWA for the Labim Booking OS. Hotel, room, nightly rate,
availability, and payment-instruction data is retrieved from the Flask service;
this app contains no seeded hotel or room records.

In production, this Flutter app serves the hotel search and booking experience
at `/`, with **Hotels** selected first, **Apartment** for the short-stay sample
preview at `/apartment`, **Homes** for the rental preview at `/rental`, and
**Land/Properties** for sample land listings at `/land-properties`. These
category previews do not connect to live inventory or accept enquiries. The old
`/book` URL redirects to `/`; `/book-app` also
opens the hotel booking experience for backward compatibility. The hotel staff
portal is at `/book.admin`. Installable PWA launches open `/`. Add
`?hotel=<slug>` to the homepage to link directly to a hotel. The PWA uses
the current page's origin for the backend by default, so the Render service URL
does not need to be compiled into the app.

The **Apartment**, **Homes**, and **Land/Properties** tabs are currently
mockups with clearly labeled sample listings. The Homes page has a simulated
inspection-choice flow. These previews do not connect to rental data, send
WhatsApp messages, accept enquiries, or collect rent or fees. The separate
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
`Dockerfile`. Configure the rooms app's Hotel button with the deployed root URL.
`/book` redirects to the root homepage.
