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

void main() {
  testWidgets('shows live hotel search and empty results state', (
    tester,
  ) async {
    await tester.pumpWidget(
      HotelBookingApp(bookingPage: HotelBookingPage(api: _EmptyBookingApi())),
    );
    await tester.pumpAndSettle();

    expect(find.text('HAIDWARE'), findsOneWidget);
    expect(find.textContaining('A better stay'), findsOneWidget);
    expect(find.text('Search hotels'), findsOneWidget);
    expect(find.text('No hotels match this search'), findsOneWidget);
  });
}
