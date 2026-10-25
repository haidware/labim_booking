import 'dart:convert';

import 'package:http/http.dart' as http;

const apiBaseUrl = String.fromEnvironment('API_BASE_URL', defaultValue: '');

class BookingApiException implements Exception {
  const BookingApiException(this.message);

  final String message;

  @override
  String toString() => message;
}

class Hotel {
  const Hotel({
    required this.id,
    required this.slug,
    required this.name,
    required this.address,
    required this.city,
    required this.state,
    required this.availableRoomCount,
    required this.lowestRate,
    required this.coverPhotoUrl,
  });

  factory Hotel.fromJson(Map<String, dynamic> json) {
    return Hotel(
      id: json['id']?.toString() ?? '',
      slug: json['slug']?.toString() ?? '',
      name: json['name']?.toString() ?? 'Hotel',
      address: json['address']?.toString() ?? '',
      city: json['city']?.toString() ?? '',
      state: json['state']?.toString() ?? '',
      availableRoomCount: (json['available_room_count'] as num?)?.toInt() ?? 0,
      lowestRate: (json['lowest_rate'] as num?)?.toDouble(),
      coverPhotoUrl: json['cover_photo_url']?.toString(),
    );
  }

  final String id;
  final String slug;
  final String name;
  final String address;
  final String city;
  final String state;
  final int availableRoomCount;
  final double? lowestRate;
  final String? coverPhotoUrl;

  String get location =>
      [city, state].where((part) => part.isNotEmpty).join(', ');

  String get displayAddress {
    final parts = address
        .split(',')
        .map((part) => part.trim())
        .where((part) => part.isNotEmpty)
        .toList();
    final existingParts = parts.map((part) => part.toLowerCase()).toSet();
    for (final part in [city, state]) {
      final normalized = part.trim();
      if (normalized.isNotEmpty &&
          existingParts.add(normalized.toLowerCase())) {
        parts.add(normalized);
      }
    }
    return parts.join(', ');
  }
}

class HotelRoom {
  const HotelRoom({
    required this.number,
    required this.type,
    required this.beds,
    required this.rate,
    required this.description,
    required this.photoUrls,
  });

  factory HotelRoom.fromJson(Map<String, dynamic> json) {
    return HotelRoom(
      number: json['number']?.toString() ?? '',
      type: json['type']?.toString() ?? 'Room',
      beds: (json['beds'] as num?)?.toInt() ?? 1,
      rate: (json['rate'] as num?)?.toDouble() ?? 0,
      description: json['description']?.toString() ?? '',
      photoUrls: (json['photo_urls'] as List<dynamic>? ?? const [])
          .map((photo) => photo.toString())
          .toList(),
    );
  }

  final String number;
  final String type;
  final int beds;
  final double rate;
  final String description;
  final List<String> photoUrls;
}

class BookingConfirmation {
  const BookingConfirmation({
    required this.reference,
    required this.hotelName,
    required this.roomNumber,
    required this.roomType,
    required this.checkIn,
    required this.checkOut,
    required this.amount,
    required this.bankName,
    required this.accountName,
    required this.accountNumber,
    required this.holdExpiresAt,
    required this.whatsappHandoffUrl,
    required this.emailNotificationSent,
  });

  factory BookingConfirmation.fromJson(Map<String, dynamic> json) {
    return BookingConfirmation(
      reference: json['reference']?.toString() ?? '',
      hotelName: json['hotel_name']?.toString() ?? '',
      roomNumber: json['room_number']?.toString() ?? '',
      roomType: json['room_type']?.toString() ?? '',
      checkIn: json['check_in']?.toString() ?? '',
      checkOut: json['check_out']?.toString() ?? '',
      amount: (json['amount'] as num?)?.toDouble() ?? 0,
      bankName: json['bank_name']?.toString() ?? '',
      accountName: json['account_name']?.toString() ?? '',
      accountNumber: json['account_number']?.toString() ?? '',
      holdExpiresAt: json['hold_expires_at']?.toString() ?? '',
      whatsappHandoffUrl: json['whatsapp_handoff_url']?.toString() ?? '',
      emailNotificationSent: json['email_notification_sent'] == true,
    );
  }

  final String reference;
  final String hotelName;
  final String roomNumber;
  final String roomType;
  final String checkIn;
  final String checkOut;
  final double amount;
  final String bankName;
  final String accountName;
  final String accountNumber;
  final String holdExpiresAt;
  final String whatsappHandoffUrl;
  final bool emailNotificationSent;
}

class BookingApi {
  BookingApi({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;
  final String _baseUrl =
      (apiBaseUrl.isNotEmpty
              ? apiBaseUrl
              : Uri.base.scheme == 'http' || Uri.base.scheme == 'https'
              ? Uri.base.origin
              : 'http://127.0.0.1:5000')
          .replaceFirst(RegExp(r'/$'), '');

  Uri _uri(String path, [Map<String, String>? query]) {
    return Uri.parse('$_baseUrl$path').replace(queryParameters: query);
  }

  Future<Map<String, dynamic>> _get(
    String path, [
    Map<String, String>? query,
  ]) async {
    final response = await _client.get(_uri(path, query));
    return _decode(response);
  }

  Map<String, dynamic> _decode(http.Response response) {
    final dynamic decoded;
    try {
      decoded = jsonDecode(response.body);
    } on FormatException {
      throw const BookingApiException(
        'The booking service returned an invalid response.',
      );
    }
    if (decoded is! Map<String, dynamic>) {
      throw const BookingApiException(
        'The booking service returned an invalid response.',
      );
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw BookingApiException(
        decoded['error']?.toString() ?? 'The request could not be completed.',
      );
    }
    return decoded;
  }

  Future<Map<String, dynamic>> loadConfig() async {
    return _get('/api/public/config');
  }

  Future<List<Hotel>> searchHotels({
    required String checkIn,
    required String checkOut,
    String state = '',
    String city = '',
    String priceRange = '',
  }) async {
    final result = await _get('/api/public/hotels', {
      'check_in': checkIn,
      'check_out': checkOut,
      if (state.isNotEmpty) 'state': state,
      if (city.isNotEmpty) 'city': city,
      if (priceRange.isNotEmpty) 'price_range': priceRange,
    });
    return (result['hotels'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(Hotel.fromJson)
        .toList();
  }

  Future<List<HotelRoom>> loadRooms({
    required String hotelSlug,
    required String checkIn,
    required String checkOut,
    String priceRange = '',
  }) async {
    final result = await _get(
      '/api/public/hotels/${Uri.encodeComponent(hotelSlug)}/rooms',
      {
        'check_in': checkIn,
        'check_out': checkOut,
        if (priceRange.isNotEmpty) 'price_range': priceRange,
      },
    );
    return (result['rooms'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(HotelRoom.fromJson)
        .toList();
  }

  Future<BookingConfirmation> createBooking({
    required Hotel hotel,
    required HotelRoom room,
    required String checkIn,
    required String checkOut,
    required String guestName,
    required String email,
    required String phone,
  }) async {
    final response = await _client.post(
      _uri('/api/public/bookings'),
      headers: const {'Content-Type': 'application/json'},
      body: jsonEncode({
        'hotel_id': hotel.id,
        'hotel_slug': hotel.slug,
        'room_number': room.number,
        'check_in': checkIn,
        'check_out': checkOut,
        'guest_name': guestName,
        'email': email,
        'phone': phone,
        'website': '',
      }),
    );
    final result = _decode(response);
    return BookingConfirmation.fromJson(
      result['booking'] as Map<String, dynamic>? ?? const {},
    );
  }

  void dispose() => _client.close();
}
