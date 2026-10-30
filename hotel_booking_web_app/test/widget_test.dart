import 'dart:ui' show Size;

import 'package:flutter/material.dart'
    show
        FilledButton,
        GlobalKey,
        MaterialApp,
        MaterialPageRoute,
        NavigatorState,
        Scrollable,
        Text,
        TextFormField;
import 'package:flutter_test/flutter_test.dart';
import 'package:hotel_booking_web_app/main.dart';
import 'package:hotel_booking_web_app/property_category_preview_page.dart';
import 'package:hotel_booking_web_app/rental_preview_page.dart';
import 'package:hotel_booking_web_app/services/apartment_preview_api.dart';
import 'package:hotel_booking_web_app/services/booking_api.dart';

class _EmptyBookingApi extends BookingApi {
  @override
  Future<Map<String, dynamic>> loadConfig() async => {
    'states': ['Lagos'],
    'price_ranges': [
      {'key': '10000-50000', 'label': '₦10,000–₦50,000'},
    ],
  };

  @override
  Future<List<Hotel>> searchHotels({
    required String checkIn,
    required String checkOut,
    String state = '',
    String city = '',
    String priceRange = '',
  }) async => const [];
}

class _BookingFlowApi extends _EmptyBookingApi {
  String? savedPushToken;
  String? savedPushSubscription;

  static const hotel = Hotel(
    id: '1',
    slug: 'labim-hotel',
    name: 'Labim Hotel and Suite',
    address: '12 Palm Avenue',
    city: 'Abuja',
    state: 'FCT',
    availableRoomCount: 1,
    lowestRate: 30000,
    coverPhotoUrl: null,
  );

  static const room = HotelRoom(
    number: '101',
    type: 'Standard',
    beds: 1,
    rate: 30000,
    description: '',
    photoUrls: [],
  );

  @override
  Future<List<Hotel>> searchHotels({
    required String checkIn,
    required String checkOut,
    String state = '',
    String city = '',
    String priceRange = '',
  }) async => [hotel];

  @override
  Future<List<HotelRoom>> loadRooms({
    required String hotelSlug,
    required String checkIn,
    required String checkOut,
    String priceRange = '',
  }) async => [room];

  @override
  Future<BookingConfirmation> createBooking({
    required Hotel hotel,
    required HotelRoom room,
    required String checkIn,
    required String checkOut,
    required String guestName,
    required String email,
    required String phone,
  }) async => BookingConfirmation(
    reference: '42',
    hotelName: hotel.name,
    roomNumber: room.number,
    roomType: room.type,
    checkIn: checkIn,
    checkOut: checkOut,
    amount: room.rate,
    bankName: 'Test Bank',
    accountName: 'Labim Hotel',
    accountNumber: '0123456789',
    holdExpiresAt: '2026-10-22T14:30:00',
    whatsappHandoffUrl:
        'https://example.com/api/public/whatsapp-handoff?token=test',
    emailNotificationSent: true,
    pushToken: 'signed-push-token',
    pushPublicKey: 'test-vapid-public-key',
  );

  @override
  Future<String> reportPayment({
    required BookingConfirmation confirmation,
    required String payerAccountName,
    required String payerAccountNumber,
  }) async => 'https://wa.me/2348000000000?text=payment';

  @override
  Future<void> savePushSubscription({
    required String token,
    required String subscriptionJson,
  }) async {
    savedPushToken = token;
    savedPushSubscription = subscriptionJson;
  }
}

void main() {
  test('hotel display address includes address, city, and state once', () {
    const hotel = Hotel(
      id: '1',
      slug: 'test-hotel',
      name: 'Test Hotel',
      address: '12 Palm Avenue, Abuja',
      city: 'Abuja',
      state: 'FCT',
      availableRoomCount: 0,
      lowestRate: null,
      coverPhotoUrl: null,
    );

    expect(hotel.displayAddress, '12 Palm Avenue, Abuja, FCT');
  });

  test('apartment preview applies city, state, and price filters', () async {
    final api = ApartmentPreviewApi();
    addTearDown(api.dispose);

    final lagosApartments = await api.searchHotels(
      checkIn: '2026-10-22',
      checkOut: '2026-10-23',
      city: 'lagos',
      state: 'Lagos',
      priceRange: '50000-100000',
    );

    expect(lagosApartments.map((apartment) => apartment.name), [
      'Serviced city apartment',
      'Modern studio apartment',
    ]);
  });

  testWidgets('hotel booking homepage offers hotel and homes tabs', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      HotelBookingApp(bookingPage: HotelBookingPage(api: _EmptyBookingApi())),
    );
    await tester.pumpAndSettle();

    expect(
      find.text('Your stay. Your choice. All in one place.'),
      findsOneWidget,
    );
    expect(find.text('Find. Compare. Book.'), findsOneWidget);
    expect(find.text('Your next stay starts here.'), findsOneWidget);
    expect(
      find.textContaining('Discover live available hotel rooms'),
      findsOneWidget,
    );
    expect(find.text('How Rooms works'), findsOneWidget);
    expect(
      find.text('Only onboarded hotels with active staff are listed.'),
      findsOneWidget,
    );
    expect(
      find.text(
        'Explore live available rooms and submit your booking request.',
      ),
      findsOneWidget,
    );
    expect(
      find.text('Pay to the hotel’s approved bank account.'),
      findsOneWidget,
    );
    expect(
      find.textContaining('Confirm your payment with hotel staff on WhatsApp'),
      findsOneWidget,
    );
    expect(
      find.textContaining('manage online and physical bookings'),
      findsOneWidget,
    );
    expect(find.text('Hotels'), findsOneWidget);
    expect(find.text('Apartment'), findsOneWidget);
    expect(find.text('Homes'), findsOneWidget);
    expect(find.text('Land/Properties'), findsOneWidget);
    expect(find.text('Live hotels and live available rooms'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('rental preview provides tabs back to hotels', (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const MaterialApp(home: RentalPreviewPage()));
    await tester.pumpAndSettle();

    expect(find.text('Hotels'), findsOneWidget);
    expect(find.text('Apartment'), findsOneWidget);
    expect(find.text('Homes'), findsOneWidget);
    expect(find.text('Land/Properties'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('apartment page follows the hotel search design with samples', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      const HotelBookingApp(
        bookingPage: HotelBookingPage(apartmentPreview: true),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.text('Find your apartment. Make your stay your own.'),
      findsOneWidget,
    );
    expect(find.text('Serviced city apartment'), findsOneWidget);
    expect(
      find.textContaining('PREVIEW — sample apartments only'),
      findsOneWidget,
    );
    expect(find.text('Search apartments'), findsOneWidget);
    expect(find.text('Sample apartments for your stay'), findsOneWidget);
    expect(find.text('Land/Properties'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('land and properties tab preview includes rent and sale', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      const MaterialApp(home: LandPropertiesPreviewPage()),
    );
    await tester.pumpAndSettle();

    expect(find.text('Land and properties'), findsOneWidget);
    expect(find.text('Residential plot'), findsOneWidget);
    expect(find.text('Commercial land'), findsOneWidget);
    expect(find.textContaining('for sale'), findsWidgets);
    expect(find.textContaining('per year'), findsOneWidget);
    expect(find.byTooltip('Back to Rooms home'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('property preview returns to the previous page', (tester) async {
    final navigatorKey = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      MaterialApp(navigatorKey: navigatorKey, home: const Text('Rooms home')),
    );

    for (final page in [const LandPropertiesPreviewPage()]) {
      navigatorKey.currentState!.push(
        MaterialPageRoute<void>(builder: (_) => page),
      );
      await tester.pumpAndSettle();
      expect(find.byTooltip('Back to Rooms home'), findsOneWidget);

      await tester.tap(find.byTooltip('Back to Rooms home'));
      await tester.pumpAndSettle();
      expect(find.text('Rooms home'), findsOneWidget);
    }

    expect(tester.takeException(), isNull);
  });

  testWidgets('apartment preview completes a local sample booking flow', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      const HotelBookingApp(
        bookingPage: HotelBookingPage(apartmentPreview: true),
      ),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('View apartment').first);
    await tester.tap(find.text('View apartment').first);
    await tester.pumpAndSettle();

    expect(
      find.text('Find your apartment at Serviced city apartment'),
      findsOneWidget,
    );
    expect(find.text('Available apartments'), findsOneWidget);
    expect(find.text('Select this apartment'), findsOneWidget);
    await tester.ensureVisible(find.text('Select this apartment'));
    await tester.tap(find.text('Select this apartment'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextFormField).at(0), 'Sample Guest');
    await tester.enterText(
      find.byType(TextFormField).at(1),
      'guest@example.com',
    );
    await tester.enterText(find.byType(TextFormField).at(2), '08000000000');
    await tester.ensureVisible(find.text('Preview booking request'));
    await tester.tap(find.text('Preview booking request'));
    await tester.pumpAndSettle();

    expect(find.text('Apartment booking preview'), findsOneWidget);
    expect(find.text('Sample stay'), findsOneWidget);
    expect(find.textContaining('No booking was saved'), findsOneWidget);
    expect(find.text('Back to apartments'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('rental preview keeps inspection selection local', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const MaterialApp(home: RentalPreviewPage()));
    await tester.pumpAndSettle();

    expect(
      find.textContaining('MOCKUP — sample listings only'),
      findsOneWidget,
    );
    expect(find.text('Preview inspection'), findsNWidgets(3));
    expect(find.text('no payment was collected'), findsNothing);

    await tester.scrollUntilVisible(
      find.text('Preview inspection').first,
      400,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Preview inspection').first);
    await tester.pumpAndSettle();
    expect(find.text('Preview an inspection request'), findsOneWidget);

    await tester.tap(find.text('Virtual viewing'));
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();

    expect(find.text('Inspection preview complete'), findsOneWidget);
    expect(find.textContaining('Virtual viewing selected'), findsOneWidget);
    expect(find.textContaining('no request was sent'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('hotel homepage tabs adapt to narrow screens', (tester) async {
    tester.view.physicalSize = const Size(320, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      HotelBookingApp(bookingPage: HotelBookingPage(api: _EmptyBookingApi())),
    );
    await tester.pumpAndSettle();

    expect(
      find.text('Your stay. Your choice. All in one place.'),
      findsOneWidget,
    );
    expect(find.text('Find. Compare. Book.'), findsOneWidget);
    expect(
      find.textContaining('land/properties across Nigeria'),
      findsOneWidget,
    );
    expect(find.text('Hotels'), findsOneWidget);
    expect(find.text('Apartment'), findsOneWidget);
    expect(find.text('Homes'), findsOneWidget);
    expect(find.text('Land/Properties'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('shows live hotel search and empty results state', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      HotelBookingApp(bookingPage: HotelBookingPage(api: _EmptyBookingApi())),
    );
    await tester.pumpAndSettle();

    expect(find.bySemanticsLabel('Rooms'), findsOneWidget);
    expect(find.text('HAIDWARE'), findsNothing);
    expect(
      find.text('Your stay. Your choice. All in one place.'),
      findsOneWidget,
    );
    expect(find.text('Find. Compare. Book.'), findsOneWidget);
    expect(find.text('Search hotels'), findsOneWidget);
    expect(find.text('No hotels match this search'), findsOneWidget);
    final layoutException = tester.takeException();
    expect(layoutException, isNull, reason: '$layoutException');
  });

  testWidgets(
    'booking ends with bank instructions and payment WhatsApp handoff',
    (tester) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final api = _BookingFlowApi();
      await tester.pumpWidget(
        HotelBookingApp(
          bookingPage: HotelBookingPage(
            api: api,
            whatsappLauncher: (_) async => true,
            pushSubscriptionCreator: (_) async =>
                '{"endpoint":"https://push.example.test/subscription",'
                '"keys":{"p256dh":"public-key","auth":"auth-key"}}',
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.ensureVisible(find.text('View rooms'));
      await tester.tap(find.text('View rooms'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      expect(
        find.text('Find your room at Labim Hotel and Suite'),
        findsOneWidget,
      );
      expect(find.textContaining('12 Palm Avenue, Abuja, FCT'), findsOneWidget);
      expect(find.text('Available rooms'), findsOneWidget);
      expect(find.text('Guest details'), findsOneWidget);
      expect(find.text('Select this room'), findsOneWidget);
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(
                FilledButton,
                'Request booking and get payment details',
              ),
            )
            .onPressed,
        isNull,
      );
      await tester.ensureVisible(find.text('Select this room'));
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('Select this room'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      await tester.enterText(find.byType(TextFormField).at(0), 'Guest Name');
      await tester.enterText(
        find.byType(TextFormField).at(1),
        'guest@example.com',
      );
      await tester.enterText(find.byType(TextFormField).at(2), '08000000000');
      expect(tester.takeException(), isNull);
      await tester.ensureVisible(
        find.text('Request booking and get payment details'),
      );
      await tester.tap(find.text('Request booking and get payment details'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      expect(find.text('Bank transfer details'), findsOneWidget);
      expect(find.text('Booking notifications'), findsOneWidget);
      expect(find.text('Enable booking notifications'), findsOneWidget);
      await tester.ensureVisible(find.text('Enable booking notifications'));
      await tester.tap(find.text('Enable booking notifications'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Notifications are enabled on this device'),
        findsOneWidget,
      );
      expect(api.savedPushToken, 'signed-push-token');
      expect(api.savedPushSubscription, contains('"endpoint"'));
      expect(
        find.textContaining('Your payment report will be saved'),
        findsOneWidget,
      );
      expect(find.text('Sender’s bank account name'), findsOneWidget);
      expect(find.text('Sender’s bank account number'), findsOneWidget);
      expect(find.text('Confirm payment on WhatsApp'), findsOneWidget);
      await tester.enterText(find.byType(TextFormField).first, 'Guest Name');
      await tester.enterText(find.byType(TextFormField).last, '0987654321');
      await tester.ensureVisible(find.text('Confirm payment on WhatsApp'));
      await tester.tap(find.text('Confirm payment on WhatsApp'));
      await tester.pumpAndSettle();
      expect(find.text('Please wait for your booking receipt'), findsOneWidget);
      expect(find.text('42'), findsOneWidget);
      expect(find.text('Waiting for Reception approval'), findsOneWidget);
      expect(
        find.textContaining(
          'Reception must verify your payment and approve the booking',
        ),
        findsOneWidget,
      );
      expect(find.text('Confirm payment on WhatsApp'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}
