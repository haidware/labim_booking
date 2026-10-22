import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import 'services/booking_api.dart';

void main() {
  runApp(const HotelBookingApp());
}

class HotelBookingApp extends StatelessWidget {
  const HotelBookingApp({super.key, this.bookingPage});

  final Widget? bookingPage;

  @override
  Widget build(BuildContext context) {
    const navy = Color(0xFF153D4C);
    const teal = Color(0xFF17607A);
    return MaterialApp(
      title: 'HAIDWARE Hotel Booking',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: teal,
          primary: teal,
          surface: const Color(0xFFFBFCFC),
        ),
        scaffoldBackgroundColor: const Color(0xFFFBFCFC),
        textTheme: const TextTheme(
          headlineLarge: TextStyle(
            color: navy,
            fontWeight: FontWeight.w700,
            letterSpacing: -1.5,
          ),
          headlineMedium: TextStyle(
            color: navy,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.8,
          ),
          titleLarge: TextStyle(color: navy, fontWeight: FontWeight.w700),
          titleMedium: TextStyle(color: navy, fontWeight: FontWeight.w600),
          bodyMedium: TextStyle(color: Color(0xFF596B70), height: 1.5),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.white,
          labelStyle: const TextStyle(color: Color(0xFF596B70)),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFFD8E2E5)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFFD8E2E5)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: teal, width: 1.5),
          ),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 14,
            vertical: 14,
          ),
        ),
      ),
      home: bookingPage ?? const HotelBookingPage(),
    );
  }
}

class HotelBookingPage extends StatefulWidget {
  const HotelBookingPage({super.key, this.api});

  final BookingApi? api;

  @override
  State<HotelBookingPage> createState() => _HotelBookingPageState();
}

class _HotelBookingPageState extends State<HotelBookingPage> {
  late final BookingApi _api;
  final TextEditingController _cityController = TextEditingController();
  final DateFormat _dateLabel = DateFormat('d MMM yyyy');
  final NumberFormat _naira = NumberFormat.currency(
    locale: 'en_NG',
    symbol: '₦',
    decimalDigits: 0,
  );

  late DateTime _checkIn;
  late DateTime _checkOut;
  String _stateFilter = '';
  String _priceRange = '';
  List<String> _states = const [];
  List<Map<String, String>> _priceRanges = const [];
  List<Hotel> _hotels = const [];
  List<HotelRoom> _rooms = const [];
  Hotel? _selectedHotel;
  BookingConfirmation? _confirmation;
  bool _loadingHotels = true;
  bool _loadingRooms = false;
  bool _submittingBooking = false;
  String? _error;

  String get _checkInIso => _isoDate(_checkIn);
  String get _checkOutIso => _isoDate(_checkOut);

  @override
  void initState() {
    super.initState();
    _api = widget.api ?? BookingApi();
    final today = DateTime.now();
    _checkIn = DateTime(today.year, today.month, today.day + 1);
    _checkOut = DateTime(today.year, today.month, today.day + 2);
    _bootstrap();
  }

  @override
  void dispose() {
    _api.dispose();
    _cityController.dispose();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    try {
      final config = await _api.loadConfig();
      if (!mounted) return;
      setState(() {
        _states = (config['states'] as List<dynamic>? ?? const [])
            .map((value) => value.toString())
            .toList();
        _priceRanges = (config['price_ranges'] as List<dynamic>? ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(
              (value) => {
                'key': value['key']?.toString() ?? '',
                'label': value['label']?.toString() ?? '',
              },
            )
            .toList();
      });
      await _loadHotels();
      final requestedHotel = Uri.base.queryParameters['hotel'];
      if (requestedHotel != null) {
        final match = _hotels.where((hotel) => hotel.slug == requestedHotel);
        if (match.isNotEmpty) await _openHotel(match.first);
      }
    } on BookingApiException catch (error) {
      if (mounted) {
        setState(() {
          _loadingHotels = false;
          _error = error.message;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _loadingHotels = false;
          _error = 'Could not connect to the hotel booking service.';
        });
      }
    }
  }

  Future<void> _loadHotels() async {
    setState(() {
      _loadingHotels = true;
      _error = null;
      _selectedHotel = null;
      _rooms = const [];
      _confirmation = null;
    });
    try {
      final hotels = await _api.searchHotels(
        checkIn: _checkInIso,
        checkOut: _checkOutIso,
        state: _stateFilter,
        city: _cityController.text.trim(),
        priceRange: _priceRange,
      );
      if (mounted) setState(() => _hotels = hotels);
    } on BookingApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Could not load hotels. Please retry.');
      }
    } finally {
      if (mounted) setState(() => _loadingHotels = false);
    }
  }

  Future<void> _openHotel(Hotel hotel) async {
    setState(() {
      _selectedHotel = hotel;
      _confirmation = null;
      _loadingRooms = true;
      _error = null;
    });
    try {
      final rooms = await _api.loadRooms(
        hotelSlug: hotel.slug,
        checkIn: _checkInIso,
        checkOut: _checkOutIso,
        priceRange: _priceRange,
      );
      if (mounted) setState(() => _rooms = rooms);
    } on BookingApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not load available rooms.');
    } finally {
      if (mounted) setState(() => _loadingRooms = false);
    }
  }

  Future<void> _searchRooms() async {
    final hotel = _selectedHotel;
    if (hotel == null) return;
    setState(() {
      _loadingRooms = true;
      _error = null;
    });
    try {
      final rooms = await _api.loadRooms(
        hotelSlug: hotel.slug,
        checkIn: _checkInIso,
        checkOut: _checkOutIso,
        priceRange: _priceRange,
      );
      if (mounted) setState(() => _rooms = rooms);
    } on BookingApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not search available rooms.');
    } finally {
      if (mounted) setState(() => _loadingRooms = false);
    }
  }

  Future<void> _selectDate({required bool isCheckIn}) async {
    final now = DateTime.now();
    final firstDate = DateTime(now.year, now.month, now.day);
    final initialDate = isCheckIn ? _checkIn : _checkOut;
    final picked = await showDatePicker(
      context: context,
      initialDate: initialDate.isBefore(firstDate) ? firstDate : initialDate,
      firstDate: firstDate,
      lastDate: DateTime(now.year + 2),
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: Theme.of(
            context,
          ).colorScheme.copyWith(primary: const Color(0xFF17607A)),
        ),
        child: child!,
      ),
    );
    if (picked == null) return;
    setState(() {
      if (isCheckIn) {
        _checkIn = picked;
        if (!_checkOut.isAfter(_checkIn)) {
          _checkOut = _checkIn.add(const Duration(days: 1));
        }
      } else if (picked.isAfter(_checkIn)) {
        _checkOut = picked;
      }
    });
  }

  Future<void> _requestBooking(HotelRoom room) async {
    final hotel = _selectedHotel;
    if (hotel == null) return;
    final guest = await showDialog<_GuestDetails>(
      context: context,
      builder: (context) => const _GuestDetailsDialog(),
    );
    if (guest == null) return;
    setState(() {
      _submittingBooking = true;
      _error = null;
    });
    try {
      final confirmation = await _api.createBooking(
        hotel: hotel,
        room: room,
        checkIn: _checkInIso,
        checkOut: _checkOutIso,
        guestName: guest.name,
        email: guest.email,
        phone: guest.phone,
      );
      if (mounted) setState(() => _confirmation = confirmation);
    } on BookingApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Could not submit the booking. Please retry.');
      }
    } finally {
      if (mounted) setState(() => _submittingBooking = false);
    }
  }

  void _backToHotels() {
    setState(() {
      _selectedHotel = null;
      _rooms = const [];
      _confirmation = null;
      _error = null;
    });
    _loadHotels();
  }

  String _isoDate(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          _buildHeader(),
          Expanded(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 220),
              child: _confirmation != null
                  ? _buildConfirmation(_confirmation!)
                  : _selectedHotel != null
                  ? _buildRoomsPage(_selectedHotel!)
                  : _buildHotelsPage(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: Color(0xFFE6ECEE))),
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1240),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 15),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: const Color(0xFF153D4C),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.hotel_rounded,
                    color: Colors.white,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 12),
                const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'HAIDWARE',
                      style: TextStyle(
                        color: Color(0xFF153D4C),
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.2,
                      ),
                    ),
                    Text(
                      'HOTEL BOOKING',
                      style: TextStyle(
                        color: Color(0xFF789098),
                        fontSize: 10,
                        letterSpacing: 1.25,
                      ),
                    ),
                  ],
                ),
                const Spacer(),
                const Icon(
                  Icons.lock_outline,
                  size: 16,
                  color: Color(0xFF71868C),
                ),
                const SizedBox(width: 7),
                const Text(
                  'Secure guest booking',
                  style: TextStyle(
                    color: Color(0xFF71868C),
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHotelsPage() {
    return SingleChildScrollView(
      key: const ValueKey('hotels'),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1240),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 38, 24, 56),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildHero(),
                const SizedBox(height: 27),
                _buildSearchPanel(),
                const SizedBox(height: 38),
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Find your stay',
                            style: Theme.of(context).textTheme.headlineMedium,
                          ),
                          const SizedBox(height: 5),
                          Text(
                            'Hotels and availability are updated directly from the booking system.',
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                        ],
                      ),
                    ),
                    if (!_loadingHotels && _hotels.isNotEmpty)
                      _ResultCount(count: _hotels.length),
                  ],
                ),
                const SizedBox(height: 20),
                if (_error != null) _ErrorBanner(message: _error!),
                if (_loadingHotels)
                  const _LoadingPanel(label: 'Finding available hotels…')
                else if (_hotels.isEmpty)
                  const _EmptyPanel(
                    icon: Icons.search_off_rounded,
                    title: 'No hotels match this search',
                    detail: 'Try different dates or clear one of the filters.',
                  )
                else
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final columns = constraints.maxWidth >= 980
                          ? 3
                          : constraints.maxWidth >= 640
                          ? 2
                          : 1;
                      return GridView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: _hotels.length,
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: columns,
                          crossAxisSpacing: 18,
                          mainAxisSpacing: 18,
                          childAspectRatio: columns == 1 ? 1.38 : 0.88,
                        ),
                        itemBuilder: (context, index) {
                          final hotel = _hotels[index];
                          return _HotelCard(
                            hotel: hotel,
                            naira: _naira,
                            onTap: () => _openHotel(hotel),
                          );
                        },
                      );
                    },
                  ),
                const SizedBox(height: 38),
                const _TrustFooter(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHero() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 34),
      decoration: BoxDecoration(
        color: const Color(0xFFEAF3F4),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFFDCE9EB)),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 650;
          return Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 11,
                        vertical: 7,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(30),
                      ),
                      child: const Text(
                        'NIGERIA · HOTEL COLLECTION',
                        style: TextStyle(
                          color: Color(0xFF17607A),
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1.1,
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'A better stay\nstarts here.',
                      style: Theme.of(context).textTheme.headlineLarge
                          ?.copyWith(fontSize: compact ? 34 : 46, height: 1.08),
                    ),
                    const SizedBox(height: 12),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 480),
                      child: const Text(
                        'Discover trusted hotels, check real room availability, '
                        'and request your booking in just a few steps.',
                        style: TextStyle(
                          color: Color(0xFF596B70),
                          fontSize: 15,
                          height: 1.65,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              if (!compact) ...[
                const SizedBox(width: 30),
                Container(
                  width: 160,
                  height: 160,
                  decoration: BoxDecoration(
                    color: const Color(0xFFD4E7E8),
                    borderRadius: BorderRadius.circular(80),
                  ),
                  child: const Icon(
                    Icons.apartment_rounded,
                    size: 78,
                    color: Color(0xFF17607A),
                  ),
                ),
              ],
            ],
          );
        },
      ),
    );
  }

  Widget _buildSearchPanel() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: const Color(0xFFE1E8EA)),
        borderRadius: BorderRadius.circular(17),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF153D4C).withValues(alpha: 0.04),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final fieldWidth = constraints.maxWidth >= 820
              ? (constraints.maxWidth - 48) / 4
              : constraints.maxWidth >= 500
              ? (constraints.maxWidth - 16) / 2
              : constraints.maxWidth;
          return Wrap(
            spacing: 16,
            runSpacing: 15,
            crossAxisAlignment: WrapCrossAlignment.end,
            children: [
              SizedBox(
                width: fieldWidth,
                child: _DateField(
                  label: 'CHECK IN',
                  value: _dateLabel.format(_checkIn),
                  onTap: () => _selectDate(isCheckIn: true),
                ),
              ),
              SizedBox(
                width: fieldWidth,
                child: _DateField(
                  label: 'CHECK OUT',
                  value: _dateLabel.format(_checkOut),
                  onTap: () => _selectDate(isCheckIn: false),
                ),
              ),
              SizedBox(
                width: fieldWidth,
                child: DropdownButtonFormField<String>(
                  initialValue: _stateFilter.isEmpty ? null : _stateFilter,
                  decoration: const InputDecoration(
                    labelText: 'STATE / FCT',
                    prefixIcon: Icon(Icons.location_on_outlined),
                  ),
                  hint: const Text('All states'),
                  items: _states
                      .map(
                        (state) => DropdownMenuItem(
                          value: state,
                          child: Text(state, overflow: TextOverflow.ellipsis),
                        ),
                      )
                      .toList(),
                  onChanged: (state) =>
                      setState(() => _stateFilter = state ?? ''),
                ),
              ),
              SizedBox(
                width: fieldWidth,
                child: TextField(
                  controller: _cityController,
                  textInputAction: TextInputAction.search,
                  onSubmitted: (_) => _loadHotels(),
                  decoration: const InputDecoration(
                    labelText: 'CITY',
                    hintText: 'Any city',
                    prefixIcon: Icon(Icons.location_city_outlined),
                  ),
                ),
              ),
              SizedBox(
                width: fieldWidth,
                child: DropdownButtonFormField<String>(
                  initialValue: _priceRange.isEmpty ? null : _priceRange,
                  decoration: const InputDecoration(
                    labelText: 'PRICE PER NIGHT',
                    prefixIcon: Icon(Icons.payments_outlined),
                  ),
                  hint: const Text('Any price'),
                  items: _priceRanges
                      .map(
                        (range) => DropdownMenuItem(
                          value: range['key'],
                          child: Text(
                            range['label'] ?? '',
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: (range) =>
                      setState(() => _priceRange = range ?? ''),
                ),
              ),
              SizedBox(
                width: fieldWidth,
                height: 52,
                child: FilledButton.icon(
                  onPressed: _loadingHotels ? null : _loadHotels,
                  icon: const Icon(Icons.search_rounded),
                  label: const Text('Search hotels'),
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF17607A),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildRoomsPage(Hotel hotel) {
    return SingleChildScrollView(
      key: const ValueKey('rooms'),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1240),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 32, 24, 56),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextButton.icon(
                  onPressed: _backToHotels,
                  icon: const Icon(Icons.arrow_back_rounded),
                  label: const Text('All hotels'),
                  style: TextButton.styleFrom(
                    foregroundColor: const Color(0xFF17607A),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            hotel.name,
                            style: Theme.of(context).textTheme.headlineMedium,
                          ),
                          const SizedBox(height: 7),
                          Text(
                            [
                              hotel.address,
                              hotel.location,
                            ].where((part) => part.isNotEmpty).join(' · '),
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                        ],
                      ),
                    ),
                    if (hotel.availableRoomCount > 0)
                      _ResultCount(
                        count: hotel.availableRoomCount,
                        label: 'rooms',
                      ),
                  ],
                ),
                const SizedBox(height: 25),
                _buildStaySummary(),
                const SizedBox(height: 22),
                if (_error != null) _ErrorBanner(message: _error!),
                if (_loadingRooms)
                  const _LoadingPanel(label: 'Checking room availability…')
                else if (_rooms.isEmpty)
                  const _EmptyPanel(
                    icon: Icons.bedroom_parent_outlined,
                    title: 'No listed rooms available',
                    detail:
                        'Try other dates or choose a different price range.',
                  )
                else ...[
                  Text(
                    '${_rooms.length} room${_rooms.length == 1 ? '' : 's'} available',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 16),
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final columns = constraints.maxWidth >= 980
                          ? 3
                          : constraints.maxWidth >= 640
                          ? 2
                          : 1;
                      return GridView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: _rooms.length,
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: columns,
                          crossAxisSpacing: 18,
                          mainAxisSpacing: 18,
                          childAspectRatio: columns == 1 ? 1.35 : 0.85,
                        ),
                        itemBuilder: (context, index) {
                          final room = _rooms[index];
                          return _RoomCard(
                            room: room,
                            naira: _naira,
                            nights: _checkOut.difference(_checkIn).inDays,
                            onBook: _submittingBooking
                                ? null
                                : () => _requestBooking(room),
                          );
                        },
                      );
                    },
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStaySummary() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFF1F6F7),
        borderRadius: BorderRadius.circular(14),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 600;
          return Wrap(
            spacing: 12,
            runSpacing: 12,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              _DateSummary(
                icon: Icons.login_rounded,
                label: 'ARRIVAL',
                value: _dateLabel.format(_checkIn),
              ),
              _DateSummary(
                icon: Icons.logout_rounded,
                label: 'DEPARTURE',
                value: _dateLabel.format(_checkOut),
              ),
              _DateSummary(
                icon: Icons.nights_stay_outlined,
                label: 'LENGTH OF STAY',
                value:
                    '${_checkOut.difference(_checkIn).inDays} night${_checkOut.difference(_checkIn).inDays == 1 ? '' : 's'}',
              ),
              SizedBox(
                width: compact ? constraints.maxWidth : null,
                child: OutlinedButton.icon(
                  onPressed: () async {
                    await _selectDate(isCheckIn: true);
                    await _selectDate(isCheckIn: false);
                    await _searchRooms();
                  },
                  icon: const Icon(Icons.edit_calendar_outlined, size: 17),
                  label: const Text('Change dates'),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildConfirmation(BookingConfirmation confirmation) {
    return SingleChildScrollView(
      key: const ValueKey('confirmation'),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 46),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    color: const Color(0xFFE3F3EB),
                    borderRadius: BorderRadius.circular(36),
                  ),
                  child: const Icon(
                    Icons.check_rounded,
                    size: 38,
                    color: Color(0xFF2B8556),
                  ),
                ),
                const SizedBox(height: 22),
                Text(
                  'Booking request received',
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
                const SizedBox(height: 8),
                Text(
                  'Your room is held for 30 minutes while you complete the bank transfer. '
                  'Reception will confirm the booking after verifying payment.',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 24),
                _ConfirmationCard(
                  title: 'Your booking',
                  child: Column(
                    children: [
                      _DetailRow(
                        label: 'Reference',
                        value: confirmation.reference,
                      ),
                      _DetailRow(label: 'Hotel', value: confirmation.hotelName),
                      _DetailRow(
                        label: 'Room',
                        value:
                            '${confirmation.roomType} · ${confirmation.roomNumber}',
                      ),
                      _DetailRow(
                        label: 'Stay',
                        value:
                            '${_formatIsoDate(confirmation.checkIn)} – ${_formatIsoDate(confirmation.checkOut)}',
                      ),
                      _DetailRow(
                        label: 'Total due',
                        value: _naira.format(confirmation.amount),
                        emphasized: true,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                _ConfirmationCard(
                  title: 'Bank transfer details',
                  child: Column(
                    children: [
                      _DetailRow(label: 'Bank', value: confirmation.bankName),
                      _DetailRow(
                        label: 'Account name',
                        value: confirmation.accountName,
                      ),
                      _DetailRow(
                        label: 'Account number',
                        value: confirmation.accountNumber,
                        trailing: IconButton(
                          tooltip: 'Copy account number',
                          onPressed: () => Clipboard.setData(
                            ClipboardData(text: confirmation.accountNumber),
                          ),
                          icon: const Icon(Icons.copy_rounded, size: 18),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                if (confirmation.emailNotificationSent)
                  const _InfoNote(
                    icon: Icons.mark_email_read_outlined,
                    text:
                        'The hotel reception has been notified of your request.',
                  )
                else
                  const _InfoNote(
                    icon: Icons.info_outline_rounded,
                    text:
                        'Your request is saved. Contact the hotel reception after payment.',
                  ),
                const SizedBox(height: 20),
                FilledButton.icon(
                  onPressed: () async {
                    final uri = Uri.tryParse(confirmation.whatsappUrl);
                    if (uri == null || !await launchUrl(uri)) {
                      if (mounted) {
                        setState(() => _error = 'Could not open WhatsApp.');
                      }
                    }
                  },
                  icon: const Icon(Icons.chat_rounded),
                  label: const Text('Message reception on WhatsApp'),
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF208A62),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 15),
                  ),
                ),
                const SizedBox(height: 10),
                OutlinedButton(
                  onPressed: _backToHotels,
                  child: const Text('Back to hotels'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _formatIsoDate(String value) {
    final parsed = DateTime.tryParse(value);
    return parsed == null ? value : _dateLabel.format(parsed);
  }
}

class _HotelCard extends StatelessWidget {
  const _HotelCard({
    required this.hotel,
    required this.naira,
    required this.onTap,
  });

  final Hotel hotel;
  final NumberFormat naira;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(17),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: _PhotoPanel(
                imageUrl: hotel.coverPhotoUrl,
                emptyIcon: Icons.apartment_rounded,
                label: hotel.state.isEmpty
                    ? 'HOTEL'
                    : hotel.state.toUpperCase(),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(17, 15, 17, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    hotel.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(
                      context,
                    ).textTheme.titleLarge?.copyWith(fontSize: 17),
                  ),
                  const SizedBox(height: 5),
                  Row(
                    children: [
                      const Icon(
                        Icons.location_on_outlined,
                        size: 15,
                        color: Color(0xFF82959A),
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          hotel.location.isEmpty
                              ? hotel.address
                              : hotel.location,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Color(0xFF71868C),
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      if (hotel.availableRoomCount > 0)
                        Expanded(
                          child: Text(
                            '${hotel.availableRoomCount} room${hotel.availableRoomCount == 1 ? '' : 's'} available',
                            style: const TextStyle(
                              color: Color(0xFF596B70),
                              fontSize: 12,
                            ),
                          ),
                        )
                      else
                        const Spacer(),
                      if (hotel.lowestRate != null)
                        Text.rich(
                          TextSpan(
                            children: [
                              TextSpan(
                                text: '${naira.format(hotel.lowestRate)}/',
                                style: const TextStyle(
                                  color: Color(0xFF153D4C),
                                  fontWeight: FontWeight.w800,
                                  fontSize: 15,
                                ),
                              ),
                              const TextSpan(
                                text: 'night',
                                style: TextStyle(
                                  color: Color(0xFF82959A),
                                  fontSize: 11,
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 13),
                  Row(
                    children: [
                      const Text(
                        'View rooms',
                        style: TextStyle(
                          color: Color(0xFF17607A),
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                        ),
                      ),
                      const Spacer(),
                      Container(
                        width: 30,
                        height: 30,
                        decoration: BoxDecoration(
                          color: const Color(0xFFEAF3F4),
                          borderRadius: BorderRadius.circular(15),
                        ),
                        child: const Icon(
                          Icons.arrow_forward_rounded,
                          size: 17,
                          color: Color(0xFF17607A),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RoomCard extends StatelessWidget {
  const _RoomCard({
    required this.room,
    required this.naira,
    required this.nights,
    required this.onBook,
  });

  final HotelRoom room;
  final NumberFormat naira;
  final int nights;
  final VoidCallback? onBook;

  @override
  Widget build(BuildContext context) {
    final total = room.rate * nights;
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(17),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: _PhotoPanel(
              imageUrl: room.photoUrls.isEmpty ? null : room.photoUrls.first,
              emptyIcon: Icons.bedroom_parent_rounded,
              label: 'ROOM ${room.number}',
              photoCount: room.photoUrls.length,
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(17, 15, 17, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${room.type} · Room ${room.number}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(fontSize: 17),
                ),
                const SizedBox(height: 7),
                Row(
                  children: [
                    const Icon(
                      Icons.bed_outlined,
                      color: Color(0xFF71868C),
                      size: 17,
                    ),
                    const SizedBox(width: 5),
                    Text(
                      '${room.beds} bed${room.beds == 1 ? '' : 's'}',
                      style: const TextStyle(
                        color: Color(0xFF71868C),
                        fontSize: 12,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      '${naira.format(room.rate)}/night',
                      style: const TextStyle(
                        color: Color(0xFF153D4C),
                        fontWeight: FontWeight.w800,
                        fontSize: 15,
                      ),
                    ),
                  ],
                ),
                if (room.description.isNotEmpty) ...[
                  const SizedBox(height: 9),
                  Text(
                    room.description,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Color(0xFF71868C),
                      fontSize: 12,
                      height: 1.45,
                    ),
                  ),
                ],
                const SizedBox(height: 13),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        '$nights night${nights == 1 ? '' : 's'} · ${naira.format(total)} total',
                        style: const TextStyle(
                          color: Color(0xFF596B70),
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    FilledButton(
                      onPressed: onBook,
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFF17607A),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 17,
                          vertical: 12,
                        ),
                      ),
                      child: const Text('Book'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PhotoPanel extends StatelessWidget {
  const _PhotoPanel({
    required this.imageUrl,
    required this.emptyIcon,
    required this.label,
    this.photoCount = 0,
  });

  final String? imageUrl;
  final IconData emptyIcon;
  final String label;
  final int photoCount;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        if (imageUrl != null && imageUrl!.isNotEmpty)
          Image.network(
            imageUrl!,
            fit: BoxFit.cover,
            errorBuilder: (context, error, stackTrace) => _emptyState(),
          )
        else
          _emptyState(),
        Positioned(
          left: 13,
          top: 13,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.94),
              borderRadius: BorderRadius.circular(30),
            ),
            child: Text(
              label,
              style: const TextStyle(
                color: Color(0xFF153D4C),
                fontSize: 9,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.8,
              ),
            ),
          ),
        ),
        if (photoCount > 1)
          Positioned(
            right: 12,
            top: 12,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.56),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                '$photoCount photos',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _emptyState() {
    return Container(
      color: const Color(0xFFEAF2F3),
      child: Center(
        child: Icon(emptyIcon, size: 65, color: const Color(0xFF86A8B0)),
      ),
    );
  }
}

class _DateField extends StatelessWidget {
  const _DateField({
    required this.label,
    required this.value,
    required this.onTap,
  });

  final String label;
  final String value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          prefixIcon: const Icon(Icons.calendar_month_outlined),
        ),
        child: Text(
          value,
          style: const TextStyle(
            color: Color(0xFF153D4C),
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

class _ResultCount extends StatelessWidget {
  const _ResultCount({required this.count, this.label = 'hotels'});

  final int count;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFEAF3F4),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        '$count $label',
        style: const TextStyle(
          color: Color(0xFF17607A),
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _LoadingPanel extends StatelessWidget {
  const _LoadingPanel({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 44),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE1E8EA)),
      ),
      child: Column(
        children: [
          const SizedBox(
            width: 27,
            height: 27,
            child: CircularProgressIndicator(strokeWidth: 2.5),
          ),
          const SizedBox(height: 14),
          Text(label, style: Theme.of(context).textTheme.bodyMedium),
        ],
      ),
    );
  }
}

class _EmptyPanel extends StatelessWidget {
  const _EmptyPanel({
    required this.icon,
    required this.title,
    required this.detail,
  });

  final IconData icon;
  final String title;
  final String detail;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(36),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE1E8EA)),
      ),
      child: Column(
        children: [
          Icon(icon, color: const Color(0xFF86A8B0), size: 42),
          const SizedBox(height: 12),
          Text(title, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 5),
          Text(detail, textAlign: TextAlign.center),
        ],
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 18),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF0EE),
        border: Border.all(color: const Color(0xFFF2CCC7)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline, color: Color(0xFFB5534B)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(color: Color(0xFF9F4941)),
            ),
          ),
        ],
      ),
    );
  }
}

class _DateSummary extends StatelessWidget {
  const _DateSummary({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minWidth: 150),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: const Color(0xFF17607A), size: 20),
          const SizedBox(width: 9),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(
                  color: Color(0xFF82959A),
                  fontSize: 9,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.7,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                value,
                style: const TextStyle(
                  color: Color(0xFF153D4C),
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ConfirmationCard extends StatelessWidget {
  const _ConfirmationCard({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: const Color(0xFFE1E8EA)),
        borderRadius: BorderRadius.circular(15),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({
    required this.label,
    required this.value,
    this.emphasized = false,
    this.trailing,
  });

  final String label;
  final String value;
  final bool emphasized;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          SizedBox(
            width: 130,
            child: Text(
              label,
              style: const TextStyle(color: Color(0xFF71868C), fontSize: 13),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                color: const Color(0xFF153D4C),
                fontSize: 13,
                fontWeight: emphasized ? FontWeight.w800 : FontWeight.w600,
              ),
            ),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

class _InfoNote extends StatelessWidget {
  const _InfoNote({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: const Color(0xFFF1F6F7),
        borderRadius: BorderRadius.circular(11),
      ),
      child: Row(
        children: [
          Icon(icon, color: const Color(0xFF17607A), size: 20),
          const SizedBox(width: 10),
          Expanded(child: Text(text, style: const TextStyle(fontSize: 12))),
        ],
      ),
    );
  }
}

class _TrustFooter extends StatelessWidget {
  const _TrustFooter();

  @override
  Widget build(BuildContext context) {
    return const Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(Icons.verified_user_outlined, size: 17, color: Color(0xFF82959A)),
        SizedBox(width: 8),
        Expanded(
          child: Text(
            'Room availability is checked live before every booking request.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Color(0xFF82959A), fontSize: 12),
          ),
        ),
      ],
    );
  }
}

class _GuestDetails {
  const _GuestDetails({
    required this.name,
    required this.email,
    required this.phone,
  });

  final String name;
  final String email;
  final String phone;
}

class _GuestDetailsDialog extends StatefulWidget {
  const _GuestDetailsDialog();

  @override
  State<_GuestDetailsDialog> createState() => _GuestDetailsDialogState();
}

class _GuestDetailsDialogState extends State<_GuestDetailsDialog> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _phone = TextEditingController();

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _phone.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Guest details'),
      content: SizedBox(
        width: 420,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _name,
                autofocus: true,
                maxLength: 160,
                decoration: const InputDecoration(
                  labelText: 'Full name',
                  prefixIcon: Icon(Icons.person_outline),
                  counterText: '',
                ),
                validator: (value) => (value == null || value.trim().isEmpty)
                    ? 'Enter your name'
                    : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _email,
                maxLength: 254,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(
                  labelText: 'Email address',
                  prefixIcon: Icon(Icons.mail_outline),
                  counterText: '',
                ),
                validator: (value) {
                  if (value == null ||
                      !RegExp(
                        r'^[^\s@]+@[^\s@]+\.[^\s@]+$',
                      ).hasMatch(value.trim())) {
                    return 'Enter a valid email';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _phone,
                maxLength: 40,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(
                  labelText: 'Phone number',
                  prefixIcon: Icon(Icons.phone_outlined),
                  counterText: '',
                ),
                validator: (value) => (value == null || value.trim().isEmpty)
                    ? 'Enter your phone number'
                    : null,
              ),
              const SizedBox(height: 10),
              const Text(
                'Your dates will be held for 30 minutes while you transfer payment. '
                'Reception confirms after verifying the transfer.',
                style: TextStyle(
                  color: Color(0xFF71868C),
                  fontSize: 12,
                  height: 1.5,
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            if (!_formKey.currentState!.validate()) return;
            Navigator.pop(
              context,
              _GuestDetails(
                name: _name.text.trim(),
                email: _email.text.trim(),
                phone: _phone.text.trim(),
              ),
            );
          },
          child: const Text('Request booking'),
        ),
      ],
    );
  }
}
