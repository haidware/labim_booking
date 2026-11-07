import 'dart:convert';
import 'dart:ui' show Size;

import 'package:flutter/material.dart'
    show
        Dialog,
        GlobalKey,
        Material,
        MaterialApp,
        MaterialPageRoute,
        NavigatorState,
        PageView,
        Scrollable,
        SizedBox,
        Text,
        TextFormField;
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
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
  bool bookingApproved = false;

  @override
  Future<Map<String, dynamic>> loadConfig() async => {
    'states': ['Lagos'],
    'price_ranges': [
      {'key': '10000-50000', 'label': '₦10,000–₦50,000'},
    ],
    'push_public_key': 'test-vapid-public-key',
  };

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
    description: 'A quiet city hotel with breakfast.',
    photoUrls: [
      'https://example.com/hotel-front.jpg',
      'https://example.com/hotel-lobby.jpg',
    ],
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
  Future<Map<String, dynamic>> savePushSubscription({
    required String token,
    required String subscriptionJson,
  }) async {
    savedPushToken = token;
    savedPushSubscription = subscriptionJson;
    return {
      'enabled': true,
      'booking_approved': false,
      'notification_sent': false,
    };
  }

  @override
  Future<Map<String, dynamic>> getBookingStatus({required String token}) async {
    expect(token, 'signed-push-token');
    return {
      'status': bookingApproved ? 'approved' : 'pending',
      'booking_approved': bookingApproved,
      'notification_sent': bookingApproved,
      'receipt_url': bookingApproved
          ? 'https://example.com/booking/receipt?token=approved'
          : '',
    };
  }
}

class _ApartmentFlowApi extends _EmptyBookingApi {
  static const apartment = Hotel(
    id: 'shortlet-1',
    slug: 'serviced-city-apartment',
    name: 'Serviced city apartment',
    address: '12 Palm Avenue',
    city: 'Lagos',
    state: 'Lagos',
    availableRoomCount: 1,
    lowestRate: 75000,
    coverPhotoUrl: null,
    managerWhatsapp: '+2348012345678',
  );

  static const unit = HotelRoom(
    number: 'serviced-city-apartment',
    type: '2 bedroom shortlet',
    beds: 2,
    rate: 75000,
    description: 'Furnished shortlet apartment.',
    photoUrls: [],
  );

  @override
  Future<List<Hotel>> searchHotels({
    required String checkIn,
    required String checkOut,
    String state = '',
    String city = '',
    String priceRange = '',
  }) async => [apartment];

  @override
  Future<List<HotelRoom>> loadRooms({
    required String hotelSlug,
    required String checkIn,
    required String checkOut,
    String priceRange = '',
  }) async => [unit];
}

class _ManyRoomsBookingApi extends _EmptyBookingApi {
  static const hotel = Hotel(
    id: 'hotel-many-rooms',
    slug: 'hotel-many-rooms',
    name: 'Hotel with Many Rooms',
    address: '12 Palm Avenue',
    city: 'Abuja',
    state: 'FCT',
    availableRoomCount: 12,
    lowestRate: 30000,
    coverPhotoUrl: null,
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
  }) async => List.generate(
    12,
    (index) => HotelRoom(
      number: '${101 + index}',
      type: 'Standard',
      beds: 1,
      rate: 30000,
      description: '',
      photoUrls: index == 0
          ? const [
              'https://example.com/room-101.jpg',
              'https://example.com/room-101-window.jpg',
            ]
          : const [],
      videoUrl: index == 0 ? 'https://example.com/room-101.mp4' : null,
    ),
  );
}

void main() {
  test('hotel JSON includes its description and photo gallery', () {
    final hotel = Hotel.fromJson({
      'id': '1',
      'slug': 'test-hotel',
      'name': 'Test Hotel',
      'address': '12 Palm Avenue',
      'city': 'Abuja',
      'state': 'FCT',
      'available_room_count': 20,
      'lowest_rate': 30000,
      'cover_photo_url': 'https://example.com/hotel-front.jpg',
      'description': 'A quiet city hotel.',
      'photo_urls': [
        'https://example.com/hotel-front.jpg',
        'https://example.com/hotel-lobby.jpg',
      ],
    });

    expect(hotel.availableRoomCount, 20);
    expect(hotel.description, 'A quiet city hotel.');
    expect(hotel.photoUrls, [
      'https://example.com/hotel-front.jpg',
      'https://example.com/hotel-lobby.jpg',
    ]);
  });

  test('room JSON includes the optional video in its media gallery', () {
    final room = HotelRoom.fromJson({
      'number': '101',
      'type': 'Standard',
      'beds': 1,
      'rate': 30000,
      'photo_urls': ['https://example.com/room-1.jpg'],
      'video_url': 'https://example.com/room-tour.mp4',
    });

    expect(room.photoUrls, ['https://example.com/room-1.jpg']);
    expect(room.videoUrl, 'https://example.com/room-tour.mp4');
  });

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

  test(
    'apartment API sends search filters to the live listings endpoint',
    () async {
      final api = ApartmentPreviewApi(
        client: MockClient((request) async {
          expect(request.url.path, '/api/public/apartments');
          expect(request.url.queryParameters['city'], 'lagos');
          expect(request.url.queryParameters['state'], 'Lagos');
          expect(request.url.queryParameters['price_range'], '50000-100000');
          return http.Response(
            jsonEncode({
              'apartments': [
                {
                  'id': 'shortlet-1',
                  'slug': 'serviced-city-apartment',
                  'name': 'Serviced city apartment',
                  'address': '12 Palm Avenue',
                  'city': 'Lagos',
                  'state': 'Lagos',
                  'available_room_count': 1,
                  'lowest_rate': 75000,
                  'manager_whatsapp': '+2348012345678',
                },
              ],
            }),
            200,
          );
        }),
      );
      addTearDown(api.dispose);

      final apartments = await api.searchHotels(
        checkIn: '2026-10-22',
        checkOut: '2026-10-23',
        city: 'lagos',
        state: 'Lagos',
        priceRange: '50000-100000',
      );

      expect(apartments.single.name, 'Serviced city apartment');
      expect(apartments.single.managerWhatsapp, '+2348012345678');
    },
  );

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
    expect(find.text('Apartment Admin'), findsNothing);
    expect(find.text('Homes'), findsOneWidget);
    expect(find.text('Land/Properties'), findsOneWidget);
    expect(find.text('Live hotels'), findsOneWidget);
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

  testWidgets('apartment page shows live shortlet search and admin access', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      HotelBookingApp(
        bookingPage: HotelBookingPage(
          api: _ApartmentFlowApi(),
          apartmentPreview: true,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.text('Find your apartment. Make your stay your own.'),
      findsOneWidget,
    );
    expect(find.byTooltip('Apartment Admin'), findsOneWidget);
    expect(
      find.textContaining('Shortlet stays require manager confirmation'),
      findsOneWidget,
    );
    expect(find.text('Search apartments'), findsOneWidget);
    expect(find.text('Shortlet apartments'), findsOneWidget);
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

  testWidgets(
    'apartment flow opens WhatsApp with a manual availability request',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      Uri? whatsappUri;
      await tester.pumpWidget(
        HotelBookingApp(
          bookingPage: HotelBookingPage(
            api: _ApartmentFlowApi(),
            apartmentPreview: true,
            whatsappLauncher: (uri) async {
              whatsappUri = uri;
              return true;
            },
          ),
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
      await tester.enterText(find.byType(TextFormField).at(1), '08000000000');
      await tester.ensureVisible(find.text('Request availability on WhatsApp'));
      await tester.tap(find.text('Request availability on WhatsApp'));
      await tester.pumpAndSettle();

      expect(whatsappUri?.host, 'wa.me');
      expect(whatsappUri?.path, '/2348012345678');
      expect(whatsappUri?.queryParameters['text'], contains('Sample Guest'));
      expect(whatsappUri?.queryParameters['text'], contains('08000000000'));
      expect(
        whatsappUri?.queryParameters['text'],
        contains('Please confirm availability'),
      );
      expect(find.textContaining('Tap Send there'), findsOneWidget);
      expect(find.text('Apartment booking preview'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

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

  testWidgets('room cards show video first and paginate five rooms at a time', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      HotelBookingApp(
        bookingPage: HotelBookingPage(
          api: _ManyRoomsBookingApi(),
          installPromptPlatform: () => 'android',
          isRunningAsInstalledApp: () => true,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('View rooms'));
    await tester.tap(find.text('View rooms'));
    await tester.pumpAndSettle();

    expect(find.text('Standard · Room 101'), findsOneWidget);
    expect(find.text('Standard · Room 105'), findsOneWidget);
    expect(find.text('Standard · Room 106'), findsNothing);
    expect(find.text('Showing 1–5 of 12 rooms'), findsOneWidget);
    expect(find.text('1'), findsOneWidget);
    expect(find.text('2'), findsOneWidget);
    expect(find.text('3'), findsOneWidget);

    final firstRoomCard = find
        .ancestor(
          of: find.text('Standard · Room 101'),
          matching: find.byType(Material),
        )
        .first;
    expect(
      find.descendant(of: firstRoomCard, matching: find.text('Video')),
      findsOneWidget,
    );
    await tester.ensureVisible(find.text('Video'));
    final firstRoomGallery = find.descendant(
      of: firstRoomCard,
      matching: find.byType(PageView),
    );
    await tester.drag(firstRoomGallery, const Offset(-260, 0));
    await tester.pumpAndSettle();
    expect(
      find.descendant(of: firstRoomCard, matching: find.text('Photo')),
      findsOneWidget,
    );

    await tester.ensureVisible(find.text('2'));
    await tester.tap(find.text('2'));
    await tester.pumpAndSettle();
    expect(find.text('Standard · Room 106'), findsOneWidget);
    expect(find.text('Standard · Room 110'), findsOneWidget);
    expect(find.text('Standard · Room 105'), findsNothing);
    expect(find.text('Showing 6–10 of 12 rooms'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('home screen setup guide stays dismissed after Got it', (
    tester,
  ) async {
    var installPromptDismissed = false;
    final api = _BookingFlowApi();
    await tester.pumpWidget(
      HotelBookingApp(
        bookingPage: HotelBookingPage(
          api: api,
          installPromptDismissed: () => installPromptDismissed,
          installPromptDismiss: () => installPromptDismissed = true,
          installPromptPlatform: () => 'android',
          notificationPermissionState: () => 'unsupported',
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Add Rooms to your Home Screen'), findsOneWidget);
    expect(find.text('Install with Google Chrome'), findsOneWidget);
    expect(find.text('Got it'), findsOneWidget);
    await tester.tap(find.text('Got it'));
    await tester.pumpAndSettle();
    expect(installPromptDismissed, isTrue);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(
      HotelBookingApp(
        bookingPage: HotelBookingPage(
          api: _BookingFlowApi(),
          installPromptDismissed: () => installPromptDismissed,
          installPromptDismiss: () => installPromptDismissed = true,
          installPromptPlatform: () => 'android',
          notificationPermissionState: () => 'unsupported',
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Add Rooms to your Home Screen'), findsNothing);
  });

  testWidgets('iPhone Home Screen guide comes before notification settings', (
    tester,
  ) async {
    var isInstalled = false;
    await tester.pumpWidget(
      HotelBookingApp(
        bookingPage: HotelBookingPage(
          api: _BookingFlowApi(),
          installPromptDismissed: () => false,
          installPromptDismiss: () {},
          installPromptPlatform: () => 'apple',
          isRunningAsInstalledApp: () => isInstalled,
          notificationPermissionState: () => 'default',
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Add Rooms to your Home Screen'), findsOneWidget);
    expect(find.text('Use Safari on your iPhone or iPad'), findsOneWidget);
    expect(find.text('Notification settings'), findsNothing);
    await tester.tap(find.text('Got it'));
    await tester.pumpAndSettle();

    isInstalled = true;
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(
      HotelBookingApp(
        bookingPage: HotelBookingPage(
          api: _BookingFlowApi(),
          installPromptDismissed: () => true,
          installPromptDismiss: () {},
          installPromptPlatform: () => 'apple',
          isRunningAsInstalledApp: () => isInstalled,
          notificationPermissionState: () => 'default',
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Notification settings'), findsOneWidget);
    expect(find.text('Allow notifications'), findsOneWidget);
    expect(find.text('Add Rooms to your Home Screen'), findsNothing);
  });

  testWidgets(
    'booking ends with bank instructions and payment WhatsApp handoff',
    (tester) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      var installPromptDismissed = false;
      var whatsappLaunchCount = 0;
      final api = _BookingFlowApi();
      await tester.pumpWidget(
        HotelBookingApp(
          bookingPage: HotelBookingPage(
            api: api,
            whatsappLauncher: (_) async {
              whatsappLaunchCount++;
              return true;
            },
            pushSubscriptionCreator: (_) async =>
                '{"endpoint":"https://push.example.test/subscription",'
                '"keys":{"p256dh":"public-key","auth":"auth-key"}}',
            installPromptDismissed: () => installPromptDismissed,
            installPromptDismiss: () => installPromptDismissed = true,
            installPromptPlatform: () => 'android',
            notificationPermissionState: () => 'default',
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('Notification settings'), findsOneWidget);
      expect(find.text('Add Rooms to your Home Screen'), findsNothing);
      expect(find.text('Allow notifications'), findsOneWidget);
      await tester.tap(find.text('Not now'));
      await tester.pumpAndSettle();
      expect(find.text('Notification settings'), findsNothing);
      expect(find.text('Add Rooms to your Home Screen'), findsOneWidget);
      expect(find.text('Install with Google Chrome'), findsOneWidget);
      expect(find.text('Allow notifications'), findsNothing);
      await tester.tap(find.text('Got it'));
      await tester.pumpAndSettle();
      expect(find.text('Add Rooms to your Home Screen'), findsNothing);
      expect(installPromptDismissed, isTrue);
      await tester.ensureVisible(find.text('View rooms'));
      expect(find.text('A quiet city hotel with breakfast.'), findsOneWidget);
      expect(find.text('1 / 2'), findsOneWidget);
      await tester.ensureVisible(find.text('1 / 2'));
      await tester.drag(find.byType(PageView).last, const Offset(-250, 0));
      await tester.pumpAndSettle();
      expect(find.text('2 / 2'), findsOneWidget);
      await tester.tap(find.text('View rooms'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      expect(
        find.text('Find your room at Labim Hotel and Suite'),
        findsOneWidget,
      );
      expect(find.textContaining('12 Palm Avenue, Abuja, FCT'), findsOneWidget);
      expect(find.text('Available rooms'), findsOneWidget);
      expect(find.text('Guest details'), findsNothing);
      expect(find.text('Select this room'), findsOneWidget);
      await tester.ensureVisible(find.text('Select this room'));
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('Select this room'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('Guest details'), findsOneWidget);
      expect(find.byType(Dialog), findsOneWidget);

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
      expect(api.savedPushToken, isNull);
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
      expect(whatsappLaunchCount, 1);
      expect(find.text('Please wait for your booking receipt'), findsOneWidget);
      expect(find.text('42'), findsOneWidget);
      expect(find.text('Waiting for Reception approval'), findsOneWidget);
      expect(
        find.textContaining('WhatsApp does not send the message automatically'),
        findsOneWidget,
      );
      expect(
        find.textContaining('tap Send to contact Reception'),
        findsOneWidget,
      );
      expect(
        find.text('Enable notifications for this booking'),
        findsOneWidget,
      );
      await tester.ensureVisible(
        find.text('Enable notifications for this booking'),
      );
      await tester.tap(find.text('Enable notifications for this booking'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining(
          'Notifications are enabled for this booking. You will be alerted',
        ),
        findsOneWidget,
      );
      expect(api.savedPushToken, 'signed-push-token');
      expect(api.savedPushSubscription, contains('"endpoint"'));
      expect(find.text('Please wait for your booking receipt'), findsOneWidget);
      api.bookingApproved = true;
      await tester.pump(const Duration(seconds: 15));
      await tester.pumpAndSettle();
      expect(find.text('Your booking is confirmed'), findsOneWidget);
      expect(find.text('Waiting for Reception approval'), findsNothing);
      expect(find.text('View booking receipt'), findsOneWidget);
      expect(
        find.textContaining(
          'Reception approved your booking and a notification was sent to this device.',
        ),
        findsOneWidget,
      );
      expect(find.text('Confirm payment on WhatsApp'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}
