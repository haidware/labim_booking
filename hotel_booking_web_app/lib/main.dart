import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import 'property_category_preview_page.dart';
import 'rental_preview_page.dart';
import 'rooms_category_tabs.dart';
import 'services/apartment_preview_api.dart';
import 'services/booking_api.dart';
import 'services/push_notifications_stub.dart'
    if (dart.library.js_interop) 'services/push_notifications_web.dart'
    as push_notifications;

void main() {
  runApp(const HotelBookingApp());
}

class HotelBookingApp extends StatelessWidget {
  const HotelBookingApp({super.key, this.bookingPage});

  final Widget? bookingPage;

  @override
  Widget build(BuildContext context) {
    const teal = Color(0xFF17607A);
    return MaterialApp(
      title: 'Rooms',
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
            color: Color(0xFF153D4C),
            fontWeight: FontWeight.w700,
            letterSpacing: -1.5,
          ),
          headlineMedium: TextStyle(
            color: Color(0xFF153D4C),
            fontWeight: FontWeight.w700,
            letterSpacing: -0.8,
          ),
          titleLarge: TextStyle(
            color: Color(0xFF153D4C),
            fontWeight: FontWeight.w700,
          ),
          titleMedium: TextStyle(
            color: Color(0xFF153D4C),
            fontWeight: FontWeight.w600,
          ),
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
      home:
          bookingPage ??
          switch (Uri.base.path) {
            '/apartment' => const HotelBookingPage(apartmentPreview: true),
            '/rental' => const RentalPreviewPage(),
            '/land-properties' => const LandPropertiesPreviewPage(),
            _ => const HotelBookingPage(),
          },
    );
  }
}

class HotelBookingPage extends StatefulWidget {
  const HotelBookingPage({
    super.key,
    this.api,
    this.apartmentPreview = false,
    this.whatsappLauncher,
    this.pushSubscriptionCreator,
  });

  final BookingApi? api;
  final bool apartmentPreview;
  final Future<bool> Function(Uri uri)? whatsappLauncher;
  final Future<String> Function(String publicKey)? pushSubscriptionCreator;

  @override
  State<HotelBookingPage> createState() => _HotelBookingPageState();
}

class _HotelBookingPageState extends State<HotelBookingPage> {
  late final BookingApi _api;
  final TextEditingController _cityController = TextEditingController();
  final TextEditingController _guestNameController = TextEditingController();
  final TextEditingController _guestEmailController = TextEditingController();
  final TextEditingController _guestPhoneController = TextEditingController();
  final TextEditingController _payerAccountNameController =
      TextEditingController();
  final TextEditingController _payerAccountNumberController =
      TextEditingController();
  final GlobalKey<FormState> _guestFormKey = GlobalKey<FormState>();
  final GlobalKey<FormState> _paymentFormKey = GlobalKey<FormState>();
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
  HotelRoom? _selectedRoom;
  BookingConfirmation? _confirmation;
  bool _loadingHotels = true;
  bool _loadingRooms = false;
  bool _submittingBooking = false;
  bool _submittingPaymentReport = false;
  bool _enablingPushNotifications = false;
  bool _pushNotificationsEnabled = false;
  bool _paymentHandoffOpened = false;
  bool _previewBookingComplete = false;
  String? _paymentWhatsappUrl;
  String? _pushNotificationMessage;
  String? _error;

  bool get _isApartmentPreview => widget.apartmentPreview;
  String get _propertyName => _isApartmentPreview ? 'apartment' : 'hotel';
  String get _propertyPlural => _isApartmentPreview ? 'apartments' : 'hotels';
  String get _unitPlural => _isApartmentPreview ? 'apartments' : 'rooms';
  String get _unitName => _isApartmentPreview ? 'apartment' : 'room';

  String get _checkInIso => _isoDate(_checkIn);
  String get _checkOutIso => _isoDate(_checkOut);

  @override
  void initState() {
    super.initState();
    _api =
        widget.api ??
        (_isApartmentPreview ? ApartmentPreviewApi() : BookingApi());
    final today = DateTime.now();
    _checkIn = DateTime(today.year, today.month, today.day + 1);
    _checkOut = DateTime(today.year, today.month, today.day + 2);
    _bootstrap();
  }

  @override
  void dispose() {
    _api.dispose();
    _cityController.dispose();
    _guestNameController.dispose();
    _guestEmailController.dispose();
    _guestPhoneController.dispose();
    _payerAccountNameController.dispose();
    _payerAccountNumberController.dispose();
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
          _error = 'Could not connect to the $_propertyName booking service.';
        });
      }
    }
  }

  Future<void> _loadHotels() async {
    setState(() {
      _loadingHotels = true;
      _error = null;
      _selectedHotel = null;
      _selectedRoom = null;
      _rooms = const [];
      _confirmation = null;
      _previewBookingComplete = false;
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
        setState(
          () => _error = 'Could not load $_propertyPlural. Please retry.',
        );
      }
    } finally {
      if (mounted) setState(() => _loadingHotels = false);
    }
  }

  Future<void> _openHotel(Hotel hotel) async {
    setState(() {
      _selectedHotel = hotel;
      _selectedRoom = null;
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
      if (mounted) {
        setState(() => _error = 'Could not load available $_unitPlural.');
      }
    } finally {
      if (mounted) setState(() => _loadingRooms = false);
    }
  }

  Future<void> _searchRooms() async {
    final hotel = _selectedHotel;
    if (hotel == null) return;
    setState(() {
      _loadingRooms = true;
      _selectedRoom = null;
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
      if (mounted) {
        setState(() => _error = 'Could not search available $_unitPlural.');
      }
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

  Future<void> _requestBooking() async {
    final hotel = _selectedHotel;
    final room = _selectedRoom;
    if (hotel == null || room == null) return;
    if (!_guestFormKey.currentState!.validate()) return;
    if (_isApartmentPreview) {
      setState(() {
        _previewBookingComplete = true;
        _error = null;
      });
      return;
    }
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
        guestName: _guestNameController.text.trim(),
        email: _guestEmailController.text.trim(),
        phone: _guestPhoneController.text.trim(),
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
    _payerAccountNameController.clear();
    _payerAccountNumberController.clear();
    setState(() {
      _selectedHotel = null;
      _selectedRoom = null;
      _rooms = const [];
      _confirmation = null;
      _previewBookingComplete = false;
      _paymentWhatsappUrl = null;
      _paymentHandoffOpened = false;
      _error = null;
    });
    _loadHotels();
  }

  Future<void> _confirmPayment(BookingConfirmation confirmation) async {
    if (_paymentWhatsappUrl == null &&
        !_paymentFormKey.currentState!.validate()) {
      return;
    }
    setState(() {
      _submittingPaymentReport = true;
      _error = null;
    });
    try {
      _paymentWhatsappUrl ??= await _api.reportPayment(
        confirmation: confirmation,
        payerAccountName: _payerAccountNameController.text.trim(),
        payerAccountNumber: _payerAccountNumberController.text.trim(),
      );
      final uri = Uri.tryParse(_paymentWhatsappUrl!);
      if (uri == null ||
          !await (widget.whatsappLauncher?.call(uri) ??
              launchUrl(uri, mode: LaunchMode.externalApplication))) {
        if (mounted) {
          setState(() {
            _error =
                'Your payment report is recorded. WhatsApp could not be opened; tap again to retry.';
          });
        }
      } else if (mounted) {
        setState(() {
          _paymentHandoffOpened = true;
          _error = null;
        });
      }
    } on BookingApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = 'Could not record the payment report. Please retry.',
        );
      }
    } finally {
      if (mounted) setState(() => _submittingPaymentReport = false);
    }
  }

  Future<void> _enableBookingNotifications(
    BookingConfirmation confirmation,
  ) async {
    setState(() {
      _enablingPushNotifications = true;
      _pushNotificationMessage = null;
    });
    try {
      final subscription = await (widget.pushSubscriptionCreator ??
          push_notifications.createPushSubscription)(confirmation.pushPublicKey);
      await _api.savePushSubscription(
        token: confirmation.pushToken,
        subscriptionJson: subscription,
      );
      if (mounted) {
        setState(() {
          _pushNotificationsEnabled = true;
          _pushNotificationMessage =
              'Notifications are enabled on this device for booking ${confirmation.reference}.';
        });
      }
    } on BookingApiException catch (error) {
      if (mounted) setState(() => _pushNotificationMessage = error.message);
    } catch (error) {
      if (mounted) {
        setState(() => _pushNotificationMessage = error.toString());
      }
    } finally {
      if (mounted) setState(() => _enablingPushNotifications = false);
    }
  }

  String _isoDate(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final page = _previewBookingComplete
        ? _buildApartmentPreviewConfirmation()
        : _confirmation != null
        ? _buildCategoryFlow(
            _paymentHandoffOpened
                ? _buildReceiptWaiting(_confirmation!)
                : _buildConfirmation(_confirmation!),
          )
        : _selectedHotel != null
        ? _buildCategoryFlow(_buildRoomsPage(_selectedHotel!))
        : _buildHotelsPage();
    return Scaffold(
      body: Column(
        children: [
          _buildHeader(),
          Expanded(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 220),
              child: page,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCategoryFlow(Widget page) {
    return Column(
      children: [
        RoomsCategoryTabs(
          activeTab: _isApartmentPreview
              ? RoomsCategoryTab.apartments
              : RoomsCategoryTab.hotels,
        ),
        Expanded(child: page),
      ],
    );
  }

  Widget _buildHeader() {
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF153D4C),
        border: Border(bottom: BorderSide(color: Color(0xFF244F5D))),
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1240),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final compact = constraints.maxWidth < 460;
              return Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: compact ? 16 : 24,
                  vertical: 15,
                ),
                child: Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFC629),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(
                        Icons.home_outlined,
                        color: Color(0xFF082A55),
                        size: 30,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Semantics(
                      label: 'Rooms',
                      child: ExcludeSemantics(
                        child: Text.rich(
                          TextSpan(
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 27,
                              fontWeight: FontWeight.w800,
                              letterSpacing: -1.1,
                            ),
                            children: [
                              TextSpan(text: 'Rooms'),
                              TextSpan(
                                text: '.',
                                style: TextStyle(color: Color(0xFFE53950)),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const Spacer(),
                    Tooltip(
                      message: _isApartmentPreview
                          ? 'Apartment booking preview'
                          : 'Secure guest booking',
                      child: const Icon(
                        Icons.lock_outline,
                        size: 16,
                        color: Color(0xFFC1D5D9),
                      ),
                    ),
                    if (!compact) ...[
                      const SizedBox(width: 7),
                      Text(
                        _isApartmentPreview
                            ? 'Apartment booking preview'
                            : 'Secure guest booking',
                        style: const TextStyle(
                          color: Color(0xFFC1D5D9),
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildHotelsPage() {
    return SingleChildScrollView(
      key: ValueKey(_propertyPlural),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1240),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 28, 16, 56),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildWelcomePanel(),
                const SizedBox(height: 28),
                if (_isApartmentPreview) ...[
                  _buildApartmentPreviewNotice(),
                  const SizedBox(height: 20),
                ],
                _buildSearchPanel(),
                const SizedBox(height: 28),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        _isApartmentPreview
                            ? 'Sample apartments for your stay'
                            : 'Live hotels and live available rooms',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                    ),
                    if (!_loadingHotels && _hotels.isNotEmpty)
                      _ResultCount(
                        count: _hotels.length,
                        label: _propertyPlural,
                      ),
                  ],
                ),
                const SizedBox(height: 16),
                if (_error != null) _ErrorBanner(message: _error!),
                if (_loadingHotels)
                  _LoadingPanel(
                    label: _isApartmentPreview
                        ? 'Loading sample apartments…'
                        : 'Finding available hotels…',
                  )
                else if (_hotels.isEmpty)
                  _EmptyPanel(
                    icon: Icons.search_off_rounded,
                    title: 'No $_propertyPlural match this search',
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
                          childAspectRatio: columns == 1 ? 1.05 : 0.88,
                        ),
                        itemBuilder: (context, index) {
                          final hotel = _hotels[index];
                          return _HotelCard(
                            hotel: hotel,
                            naira: _naira,
                            isApartmentPreview: _isApartmentPreview,
                            onTap: () => _openHotel(hotel),
                          );
                        },
                      );
                    },
                  ),
                const SizedBox(height: 38),
                _TrustFooter(isApartmentPreview: _isApartmentPreview),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildWelcomePanel() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 520;
        return Container(
          padding: EdgeInsets.all(compact ? 20 : 28),
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border.all(color: const Color(0xFFE1E8EA)),
            borderRadius: BorderRadius.circular(28),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _isApartmentPreview
                    ? 'Find your apartment. Make your stay your own.'
                    : 'Find. Compare. Book.',
                style: TextStyle(
                  color: const Color(0xFF153D4C),
                  fontSize: compact ? 30 : 42,
                  fontWeight: FontWeight.w700,
                  letterSpacing: compact ? -0.7 : -1.0,
                  height: 1.2,
                ),
              ),
              if (!_isApartmentPreview) ...[
                const SizedBox(height: 18),
                Text(
                  'Your next stay starts here.',
                  style: TextStyle(
                    color: const Color(0xFF153D4C),
                    fontSize: compact ? 21 : 26,
                    fontWeight: FontWeight.w600,
                    height: 1.3,
                  ),
                ),
                const SizedBox(height: 14),
                Text.rich(
                  TextSpan(
                    style: TextStyle(
                      color: const Color(0xFF596B70),
                      fontSize: compact ? 16 : 18,
                      height: 1.5,
                    ),
                    children: const [
                      TextSpan(text: 'Discover '),
                      TextSpan(
                        text: 'live available hotel rooms',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                      TextSpan(
                        text:
                            ', compare prices and room options, and book your preferred stay. You can also explore apartments, homes for rent and land/properties across Nigeria.',
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 18),
                Text(
                  'Your stay. Your choice. All in one place.',
                  style: TextStyle(
                    color: const Color(0xFF17607A),
                    fontSize: compact ? 17 : 20,
                    fontWeight: FontWeight.w700,
                    height: 1.4,
                  ),
                ),
              ],
              const SizedBox(height: 22),
              const Divider(height: 1, color: Color(0xFFDDE7E8)),
              const SizedBox(height: 20),
              RoomsCategoryTabs(
                activeTab: _isApartmentPreview
                    ? RoomsCategoryTab.apartments
                    : RoomsCategoryTab.hotels,
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildApartmentPreviewNotice() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF5E5),
        border: Border.all(color: const Color(0xFFE9B45F)),
        borderRadius: BorderRadius.circular(14),
      ),
      child: const Text(
        'PREVIEW — sample apartments only. Continue through the booking flow to preview the design; no booking or payment is sent or collected.',
        style: TextStyle(
          color: Color(0xFF173651),
          fontWeight: FontWeight.w600,
          height: 1.45,
        ),
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
                  isExpanded: true,
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
                  isExpanded: true,
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
                  label: Text('Search $_propertyPlural'),
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
                  label: Text('Choose a different $_propertyName'),
                  style: TextButton.styleFrom(
                    foregroundColor: const Color(0xFF17607A),
                  ),
                ),
                const SizedBox(height: 12),
                if (_isApartmentPreview) ...[
                  _buildApartmentPreviewNotice(),
                  const SizedBox(height: 18),
                ],
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Find your $_unitName at ${hotel.name}',
                            style: Theme.of(context).textTheme.headlineMedium,
                          ),
                          const SizedBox(height: 7),
                          Text(
                            'Select your dates to see the $_unitPlural listed and available.'
                            '${hotel.displayAddress.isEmpty ? '' : ' ${hotel.displayAddress}'}',
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                        ],
                      ),
                    ),
                    if (hotel.availableRoomCount > 0)
                      _ResultCount(
                        count: hotel.availableRoomCount,
                        label:
                            _isApartmentPreview && hotel.availableRoomCount == 1
                            ? 'apartment'
                            : _unitPlural,
                      ),
                  ],
                ),
                const SizedBox(height: 25),
                _buildStaySummary(),
                const SizedBox(height: 22),
                if (_error != null) _ErrorBanner(message: _error!),
                if (_loadingRooms)
                  _LoadingPanel(
                    label: _isApartmentPreview
                        ? 'Loading sample apartment details…'
                        : 'Checking room availability…',
                  )
                else if (_rooms.isEmpty)
                  _EmptyPanel(
                    icon: Icons.bedroom_parent_outlined,
                    title: 'No listed $_unitPlural available',
                    detail:
                        'Try other dates or choose a different price range.',
                  )
                else ...[
                  Text(
                    'Available $_unitPlural',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 16),
                  RadioGroup<String>(
                    groupValue: _selectedRoom?.number,
                    onChanged: (roomNumber) {
                      if (roomNumber == null) return;
                      setState(() {
                        _selectedRoom = _rooms.firstWhere(
                          (room) => room.number == roomNumber,
                        );
                      });
                    },
                    child: Column(
                      children: [
                        for (final room in _rooms)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 16),
                            child: _SelectableRoomCard(
                              room: room,
                              naira: _naira,
                              selected: _selectedRoom?.number == room.number,
                              isApartmentPreview: _isApartmentPreview,
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 4),
                  _buildGuestDetailsForm(),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildGuestDetailsForm() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE1E8EA)),
      ),
      child: Form(
        key: _guestFormKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Guest details',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 20),
            LayoutBuilder(
              builder: (context, constraints) {
                final fieldWidth = constraints.maxWidth >= 700
                    ? (constraints.maxWidth - 14) / 2
                    : constraints.maxWidth;
                return Wrap(
                  spacing: 14,
                  runSpacing: 14,
                  children: [
                    SizedBox(
                      width: fieldWidth,
                      child: TextFormField(
                        controller: _guestNameController,
                        maxLength: 160,
                        decoration: const InputDecoration(
                          labelText: 'Full name',
                          counterText: '',
                        ),
                        validator: (value) =>
                            value == null || value.trim().isEmpty
                            ? 'Enter your full name'
                            : null,
                      ),
                    ),
                    SizedBox(
                      width: fieldWidth,
                      child: TextFormField(
                        controller: _guestEmailController,
                        maxLength: 254,
                        keyboardType: TextInputType.emailAddress,
                        decoration: const InputDecoration(
                          labelText: 'Email address',
                          counterText: '',
                        ),
                        validator: (value) {
                          if (value == null ||
                              !RegExp(
                                r'^[^\s@]+@[^\s@]+\.[^\s@]+$',
                              ).hasMatch(value.trim())) {
                            return 'Enter a valid email address';
                          }
                          return null;
                        },
                      ),
                    ),
                    SizedBox(
                      width: fieldWidth,
                      child: TextFormField(
                        controller: _guestPhoneController,
                        maxLength: 40,
                        keyboardType: TextInputType.phone,
                        decoration: const InputDecoration(
                          labelText: 'Phone number',
                          counterText: '',
                        ),
                        validator: (value) =>
                            value == null || value.trim().isEmpty
                            ? 'Enter your phone number'
                            : null,
                      ),
                    ),
                  ],
                );
              },
            ),
            const SizedBox(height: 10),
            Text(
              _isApartmentPreview
                  ? 'This is a sample booking preview. No reservation or payment will be created.'
                  : 'Your dates will be held for 30 minutes while you transfer payment. Reception confirms your booking after verifying the transfer.',
              style: const TextStyle(fontSize: 13, height: 1.5),
            ),
            const SizedBox(height: 18),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _selectedRoom == null || _submittingBooking
                    ? null
                    : _requestBooking,
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF17607A),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 15),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                child: Text(
                  _submittingBooking
                      ? 'Submitting booking request…'
                      : _isApartmentPreview
                      ? 'Preview booking request'
                      : 'Request booking and get payment details',
                ),
              ),
            ),
          ],
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

  Widget _buildApartmentPreviewConfirmation() {
    final apartment = _selectedHotel!;
    final unit = _selectedRoom!;
    final nights = _checkOut.difference(_checkIn).inDays;
    return SingleChildScrollView(
      key: const ValueKey('apartment-preview-confirmation'),
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
                    color: const Color(0xFFEAF3F4),
                    borderRadius: BorderRadius.circular(36),
                  ),
                  child: const Icon(
                    Icons.visibility_outlined,
                    size: 38,
                    color: Color(0xFF17607A),
                  ),
                ),
                const SizedBox(height: 22),
                Text(
                  'Apartment booking preview',
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
                const SizedBox(height: 8),
                const Text(
                  'This preview shows the final step of the apartment flow. No booking was saved, and no payment or message was sent.',
                  style: TextStyle(color: Color(0xFF596B70), height: 1.5),
                ),
                const SizedBox(height: 20),
                _ConfirmationCard(
                  title: 'Sample stay',
                  child: Column(
                    children: [
                      _DetailRow(label: 'Apartment', value: apartment.name),
                      _DetailRow(
                        label: 'Unit',
                        value: '${unit.type} · ${unit.number}',
                      ),
                      _DetailRow(
                        label: 'Stay',
                        value:
                            '${_dateLabel.format(_checkIn)} – ${_dateLabel.format(_checkOut)}',
                      ),
                      _DetailRow(
                        label: 'Length of stay',
                        value: '$nights night${nights == 1 ? '' : 's'}',
                      ),
                      _DetailRow(
                        label: 'Sample total',
                        value: _naira.format(unit.rate * nights),
                        emphasized: true,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                _buildApartmentPreviewNotice(),
                const SizedBox(height: 20),
                FilledButton.icon(
                  onPressed: _backToHotels,
                  icon: const Icon(Icons.arrow_back_rounded),
                  label: const Text('Back to apartments'),
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF17607A),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 15),
                  ),
                ),
              ],
            ),
          ),
        ),
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
                const SizedBox(height: 14),
                const _InfoNote(
                  icon: Icons.payments_outlined,
                  text:
                      'Transfer the exact amount to the account below before the hold expires. '
                      'After paying, tap the WhatsApp button and send the prefilled payment confirmation.',
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
                if (confirmation.pushPublicKey.isNotEmpty)
                  _ConfirmationCard(
                    title: 'Booking notifications',
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          _pushNotificationMessage ??
                              'Get an alert and receipt link when Reception approves your booking.',
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                        if (!_pushNotificationsEnabled) ...[
                          const SizedBox(height: 12),
                          OutlinedButton.icon(
                            onPressed: _enablingPushNotifications
                                ? null
                                : () => _enableBookingNotifications(
                                    confirmation,
                                  ),
                            icon: const Icon(Icons.notifications_active_outlined),
                            label: Text(
                              _enablingPushNotifications
                                  ? 'Enabling notifications…'
                                  : 'Enable booking notifications',
                            ),
                          ),
                        ],
                      ],
                    ),
                  )
                else
                  const _InfoNote(
                    icon: Icons.notifications_off_outlined,
                    text:
                        'Booking notifications are not configured for this service yet.',
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
                const _InfoNote(
                  icon: Icons.info_outline_rounded,
                  text:
                      'Enter the name and account number of the bank account you paid from. '
                      'Your payment report will be saved for the hotel before WhatsApp opens.',
                ),
                const SizedBox(height: 12),
                Form(
                  key: _paymentFormKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      TextFormField(
                        controller: _payerAccountNameController,
                        maxLength: 160,
                        textCapitalization: TextCapitalization.words,
                        decoration: const InputDecoration(
                          labelText: 'Sender’s bank account name',
                          counterText: '',
                        ),
                        validator: (value) =>
                            value == null || value.trim().isEmpty
                            ? 'Enter the sender’s bank account name'
                            : null,
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _payerAccountNumberController,
                        maxLength: 10,
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                          LengthLimitingTextInputFormatter(10),
                        ],
                        decoration: const InputDecoration(
                          labelText: 'Sender’s bank account number',
                          counterText: '',
                        ),
                        validator: (value) =>
                            value == null ||
                                !RegExp(r'^\d{10}$').hasMatch(value.trim())
                            ? 'Enter the sender account number as 10 digits'
                            : null,
                      ),
                      const SizedBox(height: 16),
                      if (_error != null) _ErrorBanner(message: _error!),
                      const SizedBox(height: 8),
                      FilledButton.icon(
                        onPressed: _submittingPaymentReport
                            ? null
                            : () => _confirmPayment(confirmation),
                        icon: const Icon(Icons.chat_rounded),
                        label: Text(
                          _submittingPaymentReport
                              ? 'Recording payment report…'
                              : 'Confirm payment on WhatsApp',
                        ),
                        style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFF208A62),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 15),
                        ),
                      ),
                    ],
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

  Widget _buildReceiptWaiting(BookingConfirmation confirmation) {
    return SingleChildScrollView(
      key: const ValueKey('receipt-waiting'),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 680),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 64),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Icon(
                  Icons.hourglass_top_rounded,
                  size: 64,
                  color: Color(0xFF17607A),
                ),
                const SizedBox(height: 24),
                Text(
                  'Please wait for your booking receipt',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
                const SizedBox(height: 12),
                Text(
                  'Your payment details are recorded. WhatsApp opened with a '
                  'message for ${confirmation.hotelName}; send it there if you '
                  'have not already. Reception must verify your payment and '
                  'approve the booking before your receipt is issued.',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 24),
                _ConfirmationCard(
                  title: 'Booking request',
                  child: Column(
                    children: [
                      _DetailRow(
                        label: 'Reference',
                        value: confirmation.reference,
                      ),
                      _DetailRow(label: 'Hotel', value: confirmation.hotelName),
                      _DetailRow(
                        label: 'Status',
                        value: 'Waiting for Reception approval',
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                const _InfoNote(
                  icon: Icons.info_outline_rounded,
                  text:
                      'This is not yet a confirmed booking. Keep your reference and wait for the hotel to verify the transfer.',
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
    required this.isApartmentPreview,
    required this.onTap,
  });

  final Hotel hotel;
  final NumberFormat naira;
  final bool isApartmentPreview;
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
                    ? isApartmentPreview
                          ? 'APARTMENT'
                          : 'HOTEL'
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
                          hotel.displayAddress,
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
                            '${hotel.availableRoomCount} ${isApartmentPreview ? 'apartment' : 'room'}${hotel.availableRoomCount == 1 ? '' : 's'} available',
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
                      Text(
                        isApartmentPreview ? 'View apartment' : 'View rooms',
                        style: const TextStyle(
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

class _SelectableRoomCard extends StatelessWidget {
  const _SelectableRoomCard({
    required this.room,
    required this.naira,
    required this.selected,
    required this.isApartmentPreview,
  });

  final HotelRoom room;
  final NumberFormat naira;
  final bool selected;
  final bool isApartmentPreview;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(
          color: selected ? const Color(0xFF17607A) : const Color(0xFFE1E8EA),
          width: selected ? 2 : 1,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          LayoutBuilder(
            builder: (context, constraints) => AspectRatio(
              aspectRatio: constraints.maxWidth < 600 ? 1.8 : 5.0,
              child: room.photoUrls.isNotEmpty
                  ? Image.network(
                      room.photoUrls.first,
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) =>
                          _roomPhotoFallback(),
                    )
                  : _roomPhotoFallback(),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${room.type} · ${isApartmentPreview ? 'Unit' : 'Room'} ${room.number}',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 5),
                Text(
                  '${room.beds} bed${room.beds == 1 ? '' : 's'} · ${naira.format(room.rate)} per night',
                  style: const TextStyle(
                    color: Color(0xFF71868C),
                    fontSize: 13,
                  ),
                ),
                if (room.description.isNotEmpty) ...[
                  const SizedBox(height: 5),
                  Text(
                    room.description,
                    style: const TextStyle(
                      color: Color(0xFF71868C),
                      fontSize: 13,
                    ),
                  ),
                ],
                RadioListTile<String>(
                  value: room.number,
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  title: Text(
                    isApartmentPreview
                        ? 'Select this apartment'
                        : 'Select this room',
                    style: const TextStyle(
                      color: Color(0xFF17607A),
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _roomPhotoFallback() => Container(
    color: const Color(0xFFEAF2F3),
    child: const Center(
      child: Icon(
        Icons.bedroom_parent_rounded,
        size: 54,
        color: Color(0xFF86A8B0),
      ),
    ),
  );
}

class _PhotoPanel extends StatelessWidget {
  const _PhotoPanel({
    required this.imageUrl,
    required this.emptyIcon,
    required this.label,
  });

  final String? imageUrl;
  final IconData emptyIcon;
  final String label;

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
    return LayoutBuilder(
      builder: (context, constraints) {
        final labelWidth = constraints.maxWidth < 380 ? 96.0 : 130.0;
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(
            children: [
              SizedBox(
                width: labelWidth,
                child: Text(
                  label,
                  style: const TextStyle(
                    color: Color(0xFF71868C),
                    fontSize: 13,
                  ),
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
      },
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
  const _TrustFooter({this.isApartmentPreview = false});

  final bool isApartmentPreview;

  @override
  Widget build(BuildContext context) {
    if (isApartmentPreview) {
      return const Center(
        child: Text(
          'Sample apartment listings are shown for design preview only.',
          textAlign: TextAlign.center,
          style: TextStyle(color: Color(0xFF82959A), fontSize: 12, height: 1.5),
        ),
      );
    }

    const steps = [
      'Only onboarded hotels with active staff are listed.',
      'Explore live available rooms and submit your booking request.',
      'Pay to the hotel’s approved bank account.',
      'Confirm your payment with hotel staff on WhatsApp; staff verify payment and approve your booking.',
      'Hotel staff manage online and physical bookings to keep room availability up to date.',
    ];

    return Row(
      children: [
        Expanded(
          child: Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border.all(color: const Color(0xFFE1E8EA)),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'How Rooms works',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 10),
                for (final step in steps)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 7),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Padding(
                          padding: EdgeInsets.only(top: 7, right: 9),
                          child: Icon(
                            Icons.circle,
                            size: 5,
                            color: Color(0xFF17607A),
                          ),
                        ),
                        Expanded(
                          child: Text(
                            step,
                            style: const TextStyle(
                              color: Color(0xFF71868C),
                              fontSize: 13,
                              height: 1.5,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
