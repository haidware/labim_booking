import 'booking_api.dart';

class ApartmentPreviewApi extends BookingApi {
  static const _apartments = [
    Hotel(
      id: 'apartment-1',
      slug: 'serviced-city-apartment',
      name: 'Serviced city apartment',
      address: 'Victoria Island',
      city: 'Lagos',
      state: 'Lagos',
      availableRoomCount: 1,
      lowestRate: 95000,
      coverPhotoUrl: null,
    ),
    Hotel(
      id: 'apartment-2',
      slug: 'bright-one-bedroom-apartment',
      name: 'Bright one-bedroom apartment',
      address: 'Wuse 2',
      city: 'Abuja',
      state: 'FCT',
      availableRoomCount: 1,
      lowestRate: 68000,
      coverPhotoUrl: null,
    ),
    Hotel(
      id: 'apartment-3',
      slug: 'modern-studio-apartment',
      name: 'Modern studio apartment',
      address: 'Ikeja GRA',
      city: 'Lagos',
      state: 'Lagos',
      availableRoomCount: 1,
      lowestRate: 52000,
      coverPhotoUrl: null,
    ),
  ];

  static const _apartmentsBySlug = {
    'serviced-city-apartment': [
      HotelRoom(
        number: 'A1',
        type: 'Entire apartment',
        beds: 2,
        rate: 95000,
        description:
            'Sample short stay with a kitchen, Wi-Fi and secure parking.',
        photoUrls: [],
      ),
    ],
    'bright-one-bedroom-apartment': [
      HotelRoom(
        number: 'A2',
        type: 'One-bedroom apartment',
        beds: 1,
        rate: 68000,
        description:
            'Sample furnished apartment close to shops and restaurants.',
        photoUrls: [],
      ),
    ],
    'modern-studio-apartment': [
      HotelRoom(
        number: 'A3',
        type: 'Studio apartment',
        beds: 1,
        rate: 52000,
        description: 'Sample studio for a comfortable short stay.',
        photoUrls: [],
      ),
    ],
  };

  @override
  Future<Map<String, dynamic>> loadConfig() async => {
    'states': ['FCT', 'Lagos'],
    'price_ranges': [
      {'key': '10000-50000', 'label': '₦10,000–₦50,000'},
      {'key': '50000-100000', 'label': 'Above ₦50,000–₦100,000'},
      {'key': '100000-200000', 'label': 'Above ₦100,000–₦200,000'},
      {'key': '200000-plus', 'label': 'Above ₦200,000'},
    ],
  };

  @override
  Future<List<Hotel>> searchHotels({
    required String checkIn,
    required String checkOut,
    String state = '',
    String city = '',
    String priceRange = '',
  }) async {
    final range = switch (priceRange) {
      '10000-50000' => (10000, 50000),
      '50000-100000' => (50001, 100000),
      '100000-200000' => (100001, 200000),
      '200000-plus' => (200001, null),
      _ => null,
    };
    return _apartments.where((apartment) {
      final rate = apartment.lowestRate ?? 0;
      return (state.isEmpty || apartment.state == state) &&
          (city.isEmpty ||
              apartment.city.toLowerCase().contains(city.toLowerCase())) &&
          (range == null && priceRange.isEmpty ||
              range != null &&
                  rate >= range.$1 &&
                  (range.$2 == null || rate <= range.$2!));
    }).toList();
  }

  @override
  Future<List<HotelRoom>> loadRooms({
    required String hotelSlug,
    required String checkIn,
    required String checkOut,
    String priceRange = '',
  }) async => _apartmentsBySlug[hotelSlug] ?? const [];
}
