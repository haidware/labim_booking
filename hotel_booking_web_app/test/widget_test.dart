import 'dart:ui' show Size;

import 'package:flutter/material.dart' show TextFormField;
import 'package:flutter_test/flutter_test.dart';
import 'package:hotel_booking_web_app/main.dart';
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
  static const hotel = Hotel(
    id: '1',
    slug: 'labim-hotel',
    name: 'Labim Hotel and Suite',
    address: '',
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
    whatsappUrl: 'https://wa.me/2348000000000?text=payment',
    emailNotificationSent: true,
  );
}

void main() {
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

    expect(find.text('HAIDWARE'), findsOneWidget);
    expect(find.text('Choose a hotel'), findsOneWidget);
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

      await tester.pumpWidget(
        HotelBookingApp(bookingPage: HotelBookingPage(api: _BookingFlowApi())),
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
      await tester.ensureVisible(find.text('Book'));
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('Book'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      await tester.enterText(find.byType(TextFormField).at(0), 'Guest Name');
      await tester.enterText(
        find.byType(TextFormField).at(1),
        'guest@example.com',
      );
      await tester.enterText(find.byType(TextFormField).at(2), '08000000000');
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('Request booking'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      expect(find.text('Bank transfer details'), findsOneWidget);
      expect(
        find.textContaining('After paying, tap the WhatsApp button'),
        findsOneWidget,
      );
      expect(find.text('Confirm payment on WhatsApp'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
