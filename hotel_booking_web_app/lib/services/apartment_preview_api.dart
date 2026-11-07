import 'dart:convert';

import 'package:http/http.dart' as http;

import 'booking_api.dart';

class ApartmentPreviewApi extends BookingApi {
  ApartmentPreviewApi({super.client});

  Map<String, dynamic> _decode(http.Response response) {
    final dynamic decoded;
    try {
      decoded = jsonDecode(response.body);
    } on FormatException {
      throw const BookingApiException(
        'The apartment service returned an invalid response.',
      );
    }
    if (decoded is! Map<String, dynamic>) {
      throw const BookingApiException(
        'The apartment service returned an invalid response.',
      );
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw BookingApiException(
        decoded['error']?.toString() ??
            'Apartment listings could not be loaded.',
      );
    }
    return decoded;
  }

  List<Map<String, dynamic>> _decodeList(
    Map<String, dynamic> data,
    String key,
  ) {
    final value = data[key];
    if (value is! List || value.any((item) => item is! Map<String, dynamic>)) {
      throw const BookingApiException(
        'The apartment service returned invalid listing data.',
      );
    }
    return value.cast<Map<String, dynamic>>();
  }

  @override
  Future<List<Hotel>> searchHotels({
    required String checkIn,
    required String checkOut,
    String state = '',
    String city = '',
    String priceRange = '',
  }) async {
    final response = await httpClient.get(
      apiUri('/api/public/apartments', {
        'check_in': checkIn,
        'check_out': checkOut,
        if (state.isNotEmpty) 'state': state,
        if (city.isNotEmpty) 'city': city,
        if (priceRange.isNotEmpty) 'price_range': priceRange,
      }),
    );
    final data = _decode(response);
    return _decodeList(data, 'apartments').map(Hotel.fromJson).toList();
  }

  @override
  Future<List<HotelRoom>> loadRooms({
    required String hotelSlug,
    required String checkIn,
    required String checkOut,
    String priceRange = '',
  }) async {
    final response = await httpClient.get(
      apiUri('/api/public/apartments/${Uri.encodeComponent(hotelSlug)}/rooms', {
        'check_in': checkIn,
        'check_out': checkOut,
        if (priceRange.isNotEmpty) 'price_range': priceRange,
      }),
    );
    final data = _decode(response);
    return _decodeList(data, 'rooms').map(HotelRoom.fromJson).toList();
  }
}
