import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:video_player/video_player.dart';

import 'property_category_preview_page.dart';
import 'rental_preview_page.dart';
import 'rooms_category_tabs.dart';
import 'services/apartment_preview_api.dart';
import 'services/booking_api.dart';
import 'services/pwa_install_prompt_stub.dart'
    if (dart.library.js_interop) 'services/pwa_install_prompt_web.dart'
    as pwa_install_prompt;
import 'services/video_fullscreen.dart' as video_fullscreen;
import 'services/push_notifications_stub.dart'
    if (dart.library.js_interop) 'services/push_notifications_web.dart'
    as push_notifications;
import 'services/whatsapp_popup_stub.dart'
    if (dart.library.js_interop) 'services/whatsapp_popup_web.dart'
    as whatsapp_popup;

void main() {
  runApp(const HotelBookingApp());
}

class _ApartmentApplicationDetails {
  const _ApartmentApplicationDetails({
    required this.name,
    required this.phone,
    required this.location,
  });

  final String name;
  final String phone;
  final String location;
}

class _ApartmentApplicationDialog extends StatefulWidget {
  const _ApartmentApplicationDialog({required this.openHandoffWindow});

  final void Function() openHandoffWindow;

  @override
  State<_ApartmentApplicationDialog> createState() =>
      _ApartmentApplicationDialogState();
}

class _ApartmentApplicationDialogState
    extends State<_ApartmentApplicationDialog> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _locationController = TextEditingController();

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _locationController.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    widget.openHandoffWindow();
    Navigator.of(context).pop(
      _ApartmentApplicationDetails(
        name: _nameController.text.trim(),
        phone: _phoneController.text.trim(),
        location: _locationController.text.trim(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      scrollable: true,
      title: const Text('Apply to list a shortlet'),
      content: SizedBox(
        width: 440,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Owners and managers can apply to list their apartments. '
                'Your details will be sent to our team on WhatsApp.',
              ),
              const SizedBox(height: 18),
              TextFormField(
                controller: _nameController,
                textCapitalization: TextCapitalization.words,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(
                  labelText: 'Your name',
                  prefixIcon: Icon(Icons.person_outline),
                ),
                validator: (value) => value == null || value.trim().isEmpty
                    ? 'Enter your name.'
                    : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _phoneController,
                keyboardType: TextInputType.phone,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(
                  labelText: 'Phone number',
                  hintText: '+2348012345678',
                  prefixIcon: Icon(Icons.phone_outlined),
                ),
                validator: (value) {
                  final digits = (value ?? '').replaceAll(RegExp(r'\D'), '');
                  return digits.length < 7 || digits.length > 15
                      ? 'Enter a valid phone number.'
                      : null;
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _locationController,
                textCapitalization: TextCapitalization.words,
                textInputAction: TextInputAction.done,
                decoration: const InputDecoration(
                  labelText: 'Apartment location',
                  hintText: 'City, state and area',
                  prefixIcon: Icon(Icons.location_on_outlined),
                ),
                validator: (value) => value == null || value.trim().isEmpty
                    ? 'Enter the apartment location.'
                    : null,
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton.icon(
          onPressed: _submit,
          icon: const Icon(Icons.chat_outlined),
          label: const Text('Continue to WhatsApp'),
        ),
      ],
    );
  }
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
    this.installPromptDismissed,
    this.installPromptDismiss,
    this.installPromptPlatform,
    this.isRunningAsInstalledApp,
    this.notificationPermissionState,
    this.existingPushSubscriptionLoader,
  });

  final BookingApi? api;
  final bool apartmentPreview;
  final Future<bool> Function(Uri uri)? whatsappLauncher;
  final Future<String> Function(String publicKey)? pushSubscriptionCreator;
  final bool Function()? installPromptDismissed;
  final void Function()? installPromptDismiss;
  final String Function()? installPromptPlatform;
  final bool Function()? isRunningAsInstalledApp;
  final String Function()? notificationPermissionState;
  final Future<String> Function()? existingPushSubscriptionLoader;

  @override
  State<HotelBookingPage> createState() => _HotelBookingPageState();
}

class _HotelBookingPageState extends State<HotelBookingPage>
    with WidgetsBindingObserver {
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
  bool _enablingBookingNotifications = false;
  bool _pushSubscriptionLinked = false;
  bool _paymentHandoffOpened = false;
  bool _bookingApproved = false;
  bool _checkingBookingStatus = false;
  int _roomPage = 0;
  static const _roomsPerPage = 5;
  String _pushPublicKey = '';
  String? _pendingPushSubscription;
  String? _paymentWhatsappUrl;
  String? _pushNotificationMessage;
  String? _bookingStatusError;
  String? _bookingReceiptUrl;
  Timer? _bookingStatusTimer;
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
    WidgetsBinding.instance.addObserver(this);
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
    WidgetsBinding.instance.removeObserver(this);
    _bookingStatusTimer?.cancel();
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
        _pushPublicKey = config['push_public_key']?.toString() ?? '';
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
      if (!_isApartmentPreview) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _showFirstVisitPrompts();
        });
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
      _roomPage = 0;
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
    } catch (error, stackTrace) {
      debugPrint('Booking status refresh failed: $error\n$stackTrace');
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
      _roomPage = 0;
      _confirmation = null;
      _loadingRooms = true;
      _rooms = const [];
      _error = null;
    });
    try {
      final rooms = await _api.loadRooms(
        hotelSlug: hotel.slug,
        checkIn: _checkInIso,
        checkOut: _checkOutIso,
        priceRange: _priceRange,
      );
      if (mounted) {
        setState(() {
          _rooms = rooms;
          _roomPage = 0;
        });
      }
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
      _roomPage = 0;
      _rooms = const [];
      _error = null;
    });
    try {
      final rooms = await _api.loadRooms(
        hotelSlug: hotel.slug,
        checkIn: _checkInIso,
        checkOut: _checkOutIso,
        priceRange: _priceRange,
      );
      if (mounted) {
        setState(() {
          _rooms = rooms;
          _roomPage = 0;
        });
      }
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

  Future<void> _refreshRoomsAfterAvailabilityConflict(String message) async {
    final hotel = _selectedHotel;
    if (hotel == null) return;
    setState(() {
      _loadingRooms = true;
      _selectedRoom = null;
      _roomPage = 0;
      _rooms = const [];
      _error = message;
    });
    try {
      final rooms = await _api.loadRooms(
        hotelSlug: hotel.slug,
        checkIn: _checkInIso,
        checkOut: _checkOutIso,
        priceRange: _priceRange,
      );
      if (mounted) {
        setState(() {
          _rooms = rooms;
          _error = '$message The available room list has been refreshed.';
        });
      }
    } on BookingApiException catch (error) {
      if (mounted) {
        setState(() {
          _error =
              'Room availability changed, but the latest list could not be loaded: ${error.message}';
        });
      }
    } catch (error, stackTrace) {
      debugPrint(
        'Refreshing rooms after an availability conflict failed: '
        '$error\n$stackTrace',
      );
      if (mounted) {
        setState(() {
          _error =
              'Room availability changed, but the latest list could not be loaded. Please search again.';
        });
      }
    } finally {
      if (mounted) setState(() => _loadingRooms = false);
    }
  }

  void _goToRoomPage(int page) {
    final pageCount = (_rooms.length / _roomsPerPage).ceil();
    if (page < 0 || page >= pageCount || page == _roomPage) return;
    setState(() => _roomPage = page);
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

  Future<void> _requestBooking({
    required BuildContext dialogContext,
    required StateSetter setDialogState,
  }) async {
    final hotel = _selectedHotel;
    final room = _selectedRoom;
    if (hotel == null || room == null) return;
    if (!_guestFormKey.currentState!.validate()) return;
    if (_isApartmentPreview) {
      await _requestApartmentAvailability(hotel, room);
      return;
    }
    setState(() {
      _submittingBooking = true;
      _error = null;
    });
    if (dialogContext.mounted) setDialogState(() {});
    var bookingDialogClosed = false;
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
      bookingDialogClosed = true;
      if (dialogContext.mounted) Navigator.of(dialogContext).pop();
      _linkPushSubscription(confirmation);
    } on BookingApiException catch (error) {
      if (error.statusCode == 409) {
        bookingDialogClosed = true;
        if (dialogContext.mounted) Navigator.of(dialogContext).pop();
        await _refreshRoomsAfterAvailabilityConflict(error.message);
        return;
      }
      if (mounted) setState(() => _error = error.message);
      if (dialogContext.mounted) setDialogState(() {});
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Could not submit the booking. Please retry.');
      }
      if (dialogContext.mounted) setDialogState(() {});
    } finally {
      if (mounted) setState(() => _submittingBooking = false);
      if (!bookingDialogClosed && dialogContext.mounted) {
        setDialogState(() {});
      }
    }
  }

  void _linkPushSubscription(BookingConfirmation confirmation) {
    final subscription = _pendingPushSubscription;
    if (subscription == null) return;
    unawaited(() async {
      try {
        final result = await _api.savePushSubscription(
          token: confirmation.pushToken,
          subscriptionJson: subscription,
        );
        if (mounted && _confirmation == confirmation) {
          setState(() {
            _pushSubscriptionLinked = true;
            _pushNotificationMessage = result['notification_sent'] == true
                ? 'Reception approved this booking and the alert was sent to this device.'
                : 'This device is registered for an alert when Reception approves your booking.';
          });
        }
      } on BookingApiException catch (error) {
        if (mounted && _confirmation == confirmation) {
          setState(() {
            _pushNotificationMessage =
                'Notification permission was granted, but this booking could not be linked: ${error.message}';
          });
        }
      } catch (error) {
        if (mounted && _confirmation == confirmation) {
          setState(() {
            _pushNotificationMessage =
                'Notification permission was granted, but this booking could not be linked: $error';
          });
        }
      }
    }());
  }

  Future<void> _requestApartmentAvailability(
    Hotel apartment,
    HotelRoom unit,
  ) async {
    final whatsappNumber = apartment.managerWhatsapp.replaceAll(
      RegExp(r'\D'),
      '',
    );
    if (whatsappNumber.length < 8) {
      setState(
        () => _error = 'The apartment manager has not configured WhatsApp.',
      );
      return;
    }
    final message = [
      'Hello, I would like to check availability for this shortlet.',
      'Apartment: ${apartment.name}',
      'Location: ${apartment.displayAddress}',
      'Stay: $_checkInIso to $_checkOutIso',
      'Nightly rate: ${_naira.format(unit.rate)}',
      'Guest name: ${_guestNameController.text.trim()}',
      'Guest phone: ${_guestPhoneController.text.trim()}',
      'Please confirm availability and the total price before I make any payment.',
    ].join('\n');
    final whatsappUri = Uri.https('wa.me', '/$whatsappNumber', {
      'text': message,
    });
    final handoffWindow = whatsapp_popup.openWhatsAppPopup();
    var opened = handoffWindow?.navigate(whatsappUri.toString()) == true;
    try {
      if (!opened) {
        opened =
            await (widget.whatsappLauncher?.call(whatsappUri) ??
                launchUrl(whatsappUri, mode: LaunchMode.externalApplication));
      }
    } on Exception catch (error) {
      handoffWindow?.close();
      if (mounted) {
        setState(() => _error = 'Could not open WhatsApp: $error');
      }
      return;
    }
    if (!mounted) return;
    if (!opened) {
      handoffWindow?.close();
      setState(
        () => _error =
            'WhatsApp could not be opened. Please retry or contact the apartment manager.',
      );
      return;
    }
    Navigator.of(context).pop();
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(
          content: Text(
            'WhatsApp opened with your availability request. Tap Send there to contact the manager.',
          ),
        ),
      );
  }

  Future<void> _selectRoom(String? roomNumber) async {
    if (roomNumber == null) return;
    setState(() {
      _selectedRoom = _rooms.firstWhere((room) => room.number == roomNumber);
      _error = null;
    });
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => Dialog(
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 20,
            vertical: 24,
          ),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: 620,
              maxHeight: MediaQuery.sizeOf(dialogContext).height * 0.9,
            ),
            child: SingleChildScrollView(
              child: _buildGuestDetailsForm(
                onSubmit: () => _requestBooking(
                  dialogContext: dialogContext,
                  setDialogState: setDialogState,
                ),
              ),
            ),
          ),
        ),
      ),
    );
    if (!mounted) return;
    if (_confirmation == null) {
      setState(() => _selectedRoom = null);
    }
  }

  void _backToHotels() {
    _bookingStatusTimer?.cancel();
    _payerAccountNameController.clear();
    _payerAccountNumberController.clear();
    setState(() {
      _selectedHotel = null;
      _selectedRoom = null;
      _rooms = const [];
      _confirmation = null;
      _paymentWhatsappUrl = null;
      _paymentHandoffOpened = false;
      _bookingApproved = false;
      _bookingStatusError = null;
      _bookingReceiptUrl = null;
      _error = null;
    });
    _loadHotels();
  }

  Future<void> _confirmPayment(BookingConfirmation confirmation) async {
    if (_paymentWhatsappUrl == null &&
        !_paymentFormKey.currentState!.validate()) {
      return;
    }
    final handoffWindow = whatsapp_popup.openWhatsAppPopup();
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
      var whatsappOpened =
          uri != null && handoffWindow?.navigate(uri.toString()) == true;
      if (uri != null && !whatsappOpened) {
        whatsappOpened =
            await (widget.whatsappLauncher?.call(uri) ??
                launchUrl(uri, mode: LaunchMode.externalApplication));
      }
      if (!whatsappOpened) {
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
        _startBookingStatusPolling(confirmation);
      }
    } on BookingApiException catch (error) {
      handoffWindow?.close();
      if (mounted) setState(() => _error = error.message);
    } catch (error, stackTrace) {
      handoffWindow?.close();
      debugPrint('WhatsApp payment handoff failed: $error\n$stackTrace');
      if (mounted) {
        setState(
          () => _error = 'Could not record the payment report. Please retry.',
        );
      }
    } finally {
      if (mounted) setState(() => _submittingPaymentReport = false);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final confirmation = _confirmation;
    if (state == AppLifecycleState.resumed &&
        _paymentHandoffOpened &&
        !_bookingApproved &&
        confirmation != null) {
      unawaited(_refreshBookingStatus(confirmation));
    }
  }

  void _startBookingStatusPolling(BookingConfirmation confirmation) {
    _bookingStatusTimer?.cancel();
    unawaited(_refreshBookingStatus(confirmation));
    _bookingStatusTimer = Timer.periodic(
      const Duration(seconds: 15),
      (_) => unawaited(_refreshBookingStatus(confirmation)),
    );
  }

  Future<void> _refreshBookingStatus(BookingConfirmation confirmation) async {
    if (_checkingBookingStatus || _bookingApproved) return;
    setState(() => _checkingBookingStatus = true);
    try {
      final result = await _api.getBookingStatus(token: confirmation.pushToken);
      if (!mounted) return;
      final approved = result['booking_approved'] == true;
      setState(() {
        _bookingApproved = approved;
        _bookingReceiptUrl = result['receipt_url']?.toString();
        _bookingStatusError = null;
        if (result['notification_sent'] == true) {
          _pushNotificationMessage =
              'Reception approved your booking and a notification was sent to this device.';
        }
      });
      if (approved) _bookingStatusTimer?.cancel();
    } on BookingApiException catch (error) {
      if (mounted) setState(() => _bookingStatusError = error.message);
    } catch (_) {
      if (mounted) {
        setState(
          () => _bookingStatusError =
              'Could not refresh the booking status. We will keep trying.',
        );
      }
    } finally {
      if (mounted) setState(() => _checkingBookingStatus = false);
    }
  }

  Future<void> _openBookingReceipt() async {
    final receiptUrl = _bookingReceiptUrl;
    final uri = receiptUrl == null ? null : Uri.tryParse(receiptUrl);
    if (uri == null ||
        !await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      if (mounted) {
        setState(
          () => _bookingStatusError =
              'Your booking is confirmed, but the receipt could not be opened. Please try again.',
        );
      }
    }
  }

  Future<void> _enableNotificationsForBooking(
    BookingConfirmation confirmation,
  ) async {
    setState(() {
      _enablingBookingNotifications = true;
      _pushNotificationMessage = null;
    });
    try {
      final subscription =
          await (widget.pushSubscriptionCreator ??
              push_notifications.createPushSubscription)(
            confirmation.pushPublicKey,
          );
      final result = await _api.savePushSubscription(
        token: confirmation.pushToken,
        subscriptionJson: subscription,
      );
      if (mounted) {
        setState(() {
          _pendingPushSubscription = subscription;
          _pushSubscriptionLinked = true;
          _pushNotificationMessage = result['notification_sent'] == true
              ? 'Reception already approved this booking. An alert was sent to this device.'
              : result['booking_approved'] == true
              ? 'This device is linked, but we could not confirm delivery of the approval alert. Please open the receipt using your booking link.'
              : 'Notifications are enabled for this booking. You will be alerted when Reception approves it.';
        });
      }
    } on BookingApiException catch (error) {
      if (mounted) {
        setState(() => _pushNotificationMessage = error.message);
      }
    } catch (error) {
      if (mounted) {
        setState(() => _pushNotificationMessage = error.toString());
      }
    } finally {
      if (mounted) setState(() => _enablingBookingNotifications = false);
    }
  }

  Future<void> _showFirstVisitPrompts() async {
    final isInstalled =
        (widget.isRunningAsInstalledApp ??
        pwa_install_prompt.isRunningAsInstalledApp)();
    final platform =
        (widget.installPromptPlatform ??
        pwa_install_prompt.installPromptPlatform)();
    final requiresHomeScreenInstall = platform == 'apple' && !isInstalled;
    if (requiresHomeScreenInstall) {
      await _showHomeScreenGuide();
      return;
    }

    if (_pushPublicKey.isNotEmpty) {
      final permission =
          (widget.notificationPermissionState ??
          push_notifications.notificationPermissionState)();
      if (permission == 'granted') {
        final subscription =
            await (widget.existingPushSubscriptionLoader ??
                push_notifications.loadExistingPushSubscription)();
        if (!mounted) return;
        if (subscription.isNotEmpty) {
          _pendingPushSubscription = subscription;
        } else {
          await _showNotificationPrompt(permission);
        }
      } else if (permission != 'unsupported') {
        await _showNotificationPrompt(permission);
      }
    }

    if (!mounted) return;
    if (!isInstalled) await _showHomeScreenGuide();
  }

  Future<void> _showNotificationPrompt(String permission) async {
    var requesting = false;
    String? errorMessage;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          scrollable: true,
          icon: const Icon(Icons.notifications_active_outlined),
          title: const Text('Notification settings'),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  permission == 'denied'
                      ? 'Notifications are blocked for Rooms in your browser settings. Enable them in site permissions to receive booking approval alerts.'
                      : 'Allow Rooms to notify you when Reception approves your booking. Your device will be linked to the booking when you request one.',
                ),
                if (errorMessage != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    errorMessage!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            if (permission == 'denied')
              FilledButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('Continue'),
              ),
            if (permission != 'denied') ...[
              TextButton(
                onPressed: requesting
                    ? null
                    : () => Navigator.of(dialogContext).pop(),
                child: const Text('Not now'),
              ),
              FilledButton(
                onPressed: requesting
                    ? null
                    : () async {
                        setDialogState(() {
                          requesting = true;
                          errorMessage = null;
                        });
                        try {
                          final subscription =
                              await (widget.pushSubscriptionCreator ??
                                  push_notifications.createPushSubscription)(
                                _pushPublicKey,
                              );
                          if (!dialogContext.mounted || !mounted) return;
                          setState(() {
                            _pendingPushSubscription = subscription;
                            _pushNotificationMessage =
                                'Notification permission granted. It will be linked to your booking when you request one.';
                          });
                          Navigator.of(dialogContext).pop();
                        } catch (error) {
                          setDialogState(() {
                            requesting = false;
                            errorMessage = error.toString();
                          });
                        }
                      },
                child: Text(requesting ? 'Requesting…' : 'Allow notifications'),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _showHomeScreenGuide() async {
    final isDismissed =
        (widget.installPromptDismissed ??
        pwa_install_prompt.hasDismissedInstallPrompt)();
    if (isDismissed) return;

    final platform =
        (widget.installPromptPlatform ??
        pwa_install_prompt.installPromptPlatform)();
    final platformInstructions = switch (platform) {
      'apple' => (
        'Use Safari on your iPhone or iPad',
        'Open this link in Safari. Tap the Share button, choose “Add to Home Screen”, then tap “Add”. Internet Explorer is not available on iPhone or iPad.',
      ),
      'android' => (
        'Install with Google Chrome',
        'Open this link in Chrome. Tap the menu (⋮), choose “Install app” or “Add to Home screen”, then confirm “Install”, “Add”, or “Create shortcut”.',
      ),
      _ => (
        'Add Rooms to your Home Screen',
        'Open this link in your device’s browser menu and choose “Install app” or “Add to Home screen”. Follow the browser’s confirmation steps.',
      ),
    };
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        scrollable: true,
        icon: const Icon(Icons.add_to_home_screen_outlined),
        title: const Text('Add Rooms to your Home Screen'),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                platformInstructions.$1,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              Text(platformInstructions.$2),
            ],
          ),
        ),
        actions: [
          FilledButton(
            onPressed: () => _dismissAppSetupPrompt(dialogContext),
            child: const Text('Got it'),
          ),
        ],
      ),
    );
  }

  void _dismissAppSetupPrompt(BuildContext dialogContext) {
    (widget.installPromptDismiss ?? pwa_install_prompt.dismissInstallPrompt)();
    Navigator.of(dialogContext).pop();
  }

  String _isoDate(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';

  Future<void> _openApartmentAdmin() async {
    final opened = await launchUrl(
      Uri.base.resolve('/book.admin?workspace=apartment'),
      webOnlyWindowName: '_self',
    );
    if (!opened && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Unable to open Apartment Admin.')),
      );
    }
  }

  Future<void> _applyToListApartment() async {
    whatsapp_popup.WhatsAppPopup? handoffWindow;
    var keepHandoffWindowOpen = false;
    try {
      final details = await showDialog<_ApartmentApplicationDetails>(
        context: context,
        builder: (_) => _ApartmentApplicationDialog(
          openHandoffWindow: () {
            handoffWindow = whatsapp_popup.openWhatsAppPopup();
          },
        ),
      );
      if (details == null || !mounted) return;

      final message = [
        'Hello, I would like to apply to list a shortlet apartment on Rooms.',
        'Name: ${details.name}',
        'Phone: ${details.phone}',
        'Apartment location: ${details.location}',
      ].join('\n');
      final uri = Uri.https('wa.me', '/2348127499576', {'text': message});
      var opened = handoffWindow?.navigate(uri.toString()) == true;
      keepHandoffWindowOpen = opened;
      if (!opened) {
        opened =
            await (widget.whatsappLauncher?.call(uri) ??
                launchUrl(uri, mode: LaunchMode.externalApplication));
      }
      if (opened && handoffWindow != null) {
        keepHandoffWindowOpen = true;
      }
      if (!opened && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Unable to open WhatsApp. Please try again.'),
          ),
        );
      }
    } finally {
      if (!keepHandoffWindowOpen) handoffWindow?.close();
    }
  }

  @override
  Widget build(BuildContext context) {
    final page = _confirmation != null
        ? _buildCategoryFlow(
            _paymentHandoffOpened
                ? _bookingApproved
                      ? _buildBookingApproved(_confirmation!)
                      : _buildReceiptWaiting(_confirmation!)
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
                    if (_isApartmentPreview && compact)
                      IconButton(
                        onPressed: _openApartmentAdmin,
                        tooltip: 'Apartment Admin',
                        icon: const Icon(Icons.admin_panel_settings_outlined),
                        color: Colors.white,
                      )
                    else if (_isApartmentPreview)
                      TextButton.icon(
                        onPressed: _openApartmentAdmin,
                        icon: const Icon(Icons.admin_panel_settings_outlined),
                        label: const Text('Apartment Admin'),
                        style: TextButton.styleFrom(
                          foregroundColor: Colors.white,
                        ),
                      )
                    else
                      const Tooltip(
                        message: 'Secure guest booking',
                        child: Icon(
                          Icons.lock_outline,
                          size: 16,
                          color: Color(0xFFC1D5D9),
                        ),
                      ),
                    if (!compact && !_isApartmentPreview) ...[
                      const SizedBox(width: 7),
                      Text(
                        'Secure guest booking',
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
                            ? 'Shortlet apartments'
                            : 'Live hotels',
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
                        ? 'Finding available shortlets…'
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
                          childAspectRatio: columns == 1 ? 0.88 : 0.78,
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
      child: Align(
        alignment: AlignmentDirectional.centerEnd,
        child: FilledButton.icon(
          onPressed: _applyToListApartment,
          icon: const Icon(Icons.add_home_work_outlined),
          label: const Text('Apply to list an apartment'),
          style: FilledButton.styleFrom(
            backgroundColor: const Color(0xFF17607A),
            foregroundColor: Colors.white,
          ),
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
                          if (hotel.description.isNotEmpty) ...[
                            Text(
                              hotel.description,
                              style: Theme.of(context).textTheme.bodyMedium,
                            ),
                            const SizedBox(height: 7),
                          ],
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
                    onChanged: _selectRoom,
                    child: Column(
                      children: [
                        for (final room
                            in _rooms
                                .skip(_roomPage * _roomsPerPage)
                                .take(_roomsPerPage))
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
                  if (_rooms.length > _roomsPerPage) ...[
                    const SizedBox(height: 2),
                    _buildRoomPagination(),
                  ],
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildRoomPagination() {
    final pageCount = (_rooms.length / _roomsPerPage).ceil();
    final firstRoom = _roomPage * _roomsPerPage + 1;
    final lastRoom = (_roomPage + 1) * _roomsPerPage < _rooms.length
        ? (_roomPage + 1) * _roomsPerPage
        : _rooms.length;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        runSpacing: 10,
        spacing: 12,
        children: [
          Text(
            'Showing $firstRoom–$lastRoom of ${_rooms.length} $_unitPlural',
            style: const TextStyle(color: Color(0xFF71868C), fontSize: 13),
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                tooltip: 'Previous page',
                onPressed: _roomPage == 0
                    ? null
                    : () => _goToRoomPage(_roomPage - 1),
                icon: const Icon(Icons.chevron_left_rounded),
              ),
              for (var page = 0; page < pageCount; page++)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 2),
                  child: TextButton(
                    onPressed: () => _goToRoomPage(page),
                    style: TextButton.styleFrom(
                      foregroundColor: _roomPage == page
                          ? Colors.white
                          : const Color(0xFF17607A),
                      backgroundColor: _roomPage == page
                          ? const Color(0xFF17607A)
                          : Colors.transparent,
                      minimumSize: const Size(40, 40),
                      padding: EdgeInsets.zero,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    child: Text('${page + 1}'),
                  ),
                ),
              IconButton(
                tooltip: 'Next page',
                onPressed: _roomPage >= pageCount - 1
                    ? null
                    : () => _goToRoomPage(_roomPage + 1),
                icon: const Icon(Icons.chevron_right_rounded),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildGuestDetailsForm({required VoidCallback onSubmit}) {
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
            if (_selectedRoom != null) ...[
              const SizedBox(height: 8),
              Text(
                _isApartmentPreview
                    ? 'Selected shortlet: ${_selectedHotel?.name ?? _selectedRoom!.number}'
                    : 'Selected room: ${_selectedRoom!.number}',
                style: const TextStyle(
                  color: Color(0xFF17607A),
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
            const SizedBox(height: 20),
            if (_error != null) ...[
              _ErrorBanner(message: _error!),
              const SizedBox(height: 12),
            ],
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
                    if (!_isApartmentPreview)
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
                  ? 'The manager must confirm availability. Your message opens in WhatsApp and is only sent when you tap Send. Do not pay until the manager confirms.'
                  : 'Your dates will be held for 30 minutes while you transfer payment. Reception confirms your booking after verifying the transfer.',
              style: const TextStyle(fontSize: 13, height: 1.5),
            ),
            const SizedBox(height: 18),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _selectedRoom == null || _submittingBooking
                    ? null
                    : onSubmit,
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
                      ? 'Request availability on WhatsApp'
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
                              'Notification permission can be enabled when Rooms opens. This device will be linked to this booking after you allow it.',
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
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
                if (_bookingStatusError != null) ...[
                  _ErrorBanner(message: _bookingStatusError!),
                  const SizedBox(height: 12),
                ],
                Text(
                  'Your payment details are recorded. WhatsApp does not send '
                  'the message automatically. In WhatsApp, review the '
                  'prefilled message for ${confirmation.hotelName} and tap '
                  'Send to contact Reception. Return here afterward. Reception '
                  'must verify your payment and approve the booking before '
                  'your receipt is issued.',
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
                if (confirmation.pushPublicKey.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  _ConfirmationCard(
                    title: 'Booking notifications',
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          _pushNotificationMessage ??
                              'Enable alerts on this device to know when Reception approves this booking.',
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                        if (!_pushSubscriptionLinked) ...[
                          const SizedBox(height: 12),
                          OutlinedButton.icon(
                            onPressed: _enablingBookingNotifications
                                ? null
                                : () => _enableNotificationsForBooking(
                                    confirmation,
                                  ),
                            icon: const Icon(
                              Icons.notifications_active_outlined,
                            ),
                            label: Text(
                              _enablingBookingNotifications
                                  ? 'Enabling notifications…'
                                  : 'Enable notifications for this booking',
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBookingApproved(BookingConfirmation confirmation) {
    return SingleChildScrollView(
      key: const ValueKey('booking-approved'),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 680),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 64),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Icon(
                  Icons.verified_rounded,
                  size: 64,
                  color: Color(0xFF2B8556),
                ),
                const SizedBox(height: 24),
                Text(
                  'Your booking is confirmed',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
                const SizedBox(height: 12),
                Text(
                  'Reception has verified your payment and approved your stay at ${confirmation.hotelName}.',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                if (_pushNotificationMessage != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    _pushNotificationMessage!,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ],
                if (_bookingStatusError != null) ...[
                  const SizedBox(height: 12),
                  _ErrorBanner(message: _bookingStatusError!),
                ],
                const SizedBox(height: 24),
                _ConfirmationCard(
                  title: 'Confirmed booking',
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
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                if (_bookingReceiptUrl?.isNotEmpty == true)
                  FilledButton.icon(
                    onPressed: _openBookingReceipt,
                    icon: const Icon(Icons.receipt_long_outlined),
                    label: const Text('View booking receipt'),
                  ),
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
              child: _HotelPhotoGallery(
                hotel: hotel,
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
                  if (hotel.description.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      hotel.description,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFF596B70),
                        fontSize: 12,
                        height: 1.35,
                      ),
                    ),
                  ],
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

class _RoomMediaGallery extends StatefulWidget {
  const _RoomMediaGallery({
    super.key,
    required this.room,
    required this.aspectRatio,
    required this.isApartmentPreview,
  });

  final HotelRoom room;
  final double aspectRatio;
  final bool isApartmentPreview;

  @override
  State<_RoomMediaGallery> createState() => _RoomMediaGalleryState();
}

class _RoomMediaGalleryState extends State<_RoomMediaGallery> {
  VideoPlayerController? _videoController;
  String? _videoError;
  int _currentPage = 0;
  bool _openingFullscreen = false;

  int get _mediaCount =>
      widget.room.photoUrls.length +
      ((widget.room.videoUrl?.isNotEmpty ?? false) ? 1 : 0);

  bool get _hasVideo => widget.room.videoUrl?.isNotEmpty ?? false;

  Future<void> _initializeVideo(
    String videoUrl, {
    bool autoplay = false,
  }) async {
    final controller = VideoPlayerController.networkUrl(Uri.parse(videoUrl));
    _videoController = controller;
    try {
      await controller.initialize();
      if (autoplay) await controller.play();
      if (mounted) setState(() {});
    } catch (error, stackTrace) {
      debugPrint('Room video could not be loaded: $error\n$stackTrace');
      if (mounted) {
        final mediaName = widget.isApartmentPreview ? 'apartment' : 'room';
        setState(
          () => _videoError = 'This $mediaName video could not be loaded.',
        );
      }
    }
  }

  Future<void> _openFullscreenVideo() async {
    final controller = _videoController;
    if (controller == null ||
        !controller.value.isInitialized ||
        _openingFullscreen) {
      return;
    }

    setState(() => _openingFullscreen = true);
    unawaited(video_fullscreen.enterVideoFullscreen());
    try {
      await Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          fullscreenDialog: true,
          builder: (_) => _FullscreenRoomVideoPage(
            controller: controller,
            mediaName: widget.isApartmentPreview ? 'apartment' : 'room',
          ),
        ),
      );
    } finally {
      try {
        if (controller.value.isPlaying) await controller.pause();
      } finally {
        unawaited(video_fullscreen.exitVideoFullscreen());
        if (mounted) setState(() => _openingFullscreen = false);
      }
    }
  }

  @override
  void dispose() {
    _videoController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final count = _mediaCount == 0 ? 1 : _mediaCount;
    final videoIndex = _hasVideo ? 0 : -1;
    return AspectRatio(
      aspectRatio: widget.aspectRatio,
      child: Stack(
        fit: StackFit.expand,
        children: [
          PageView.builder(
            itemCount: count,
            onPageChanged: (index) {
              setState(() => _currentPage = index);
              final videoUrl = widget.room.videoUrl;
              if (index == videoIndex &&
                  videoUrl != null &&
                  videoUrl.isNotEmpty &&
                  _videoController == null &&
                  _videoError == null) {
                _initializeVideo(videoUrl);
              }
              final controller = _videoController;
              if (index != videoIndex &&
                  controller != null &&
                  controller.value.isPlaying) {
                controller.pause();
              }
            },
            itemBuilder: (context, index) {
              if (_hasVideo && index == videoIndex) {
                return _buildVideo();
              }
              final photoIndex = index - (_hasVideo ? 1 : 0);
              if (photoIndex >= 0 &&
                  photoIndex < widget.room.photoUrls.length) {
                return Image.network(
                  widget.room.photoUrls[photoIndex],
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) =>
                      _roomPhotoFallback(),
                );
              }
              return _roomPhotoFallback();
            },
          ),
          if (count > 1)
            Positioned(
              right: 10,
              top: 10,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Text(
                  '${_currentPage + 1} / $count',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          if (_mediaCount > 0)
            Positioned(
              left: 10,
              top: 10,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      _hasVideo && _currentPage == videoIndex
                          ? Icons.videocam
                          : Icons.photo_outlined,
                      size: 15,
                      color: Colors.white,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      _hasVideo && _currentPage == videoIndex
                          ? 'Video'
                          : 'Photo',
                      style: const TextStyle(color: Colors.white, fontSize: 12),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildVideo() {
    final controller = _videoController;
    if (_videoError != null) {
      return Container(
        color: Colors.black,
        alignment: Alignment.center,
        child: Text(
          _videoError!,
          style: const TextStyle(color: Colors.white),
          textAlign: TextAlign.center,
        ),
      );
    }
    if (controller == null) {
      return ColoredBox(
        color: Colors.black,
        child: Center(
          child: IconButton.filled(
            tooltip: widget.isApartmentPreview
                ? 'Play apartment video'
                : 'Play room video',
            onPressed: () {
              final videoUrl = widget.room.videoUrl;
              if (videoUrl != null && videoUrl.isNotEmpty) {
                _initializeVideo(videoUrl, autoplay: true);
              }
            },
            style: IconButton.styleFrom(
              backgroundColor: Colors.white24,
              foregroundColor: Colors.white,
            ),
            icon: const Icon(Icons.play_arrow, size: 38),
          ),
        ),
      );
    }
    if (!controller.value.isInitialized) {
      return Container(
        color: Colors.black,
        alignment: Alignment.center,
        child: const CircularProgressIndicator(color: Colors.white),
      );
    }
    return ColoredBox(
      color: Colors.black,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Positioned.fill(
            child: FittedBox(
              fit: BoxFit.contain,
              clipBehavior: Clip.hardEdge,
              child: SizedBox(
                width: controller.value.size.width,
                height: controller.value.size.height,
                child: VideoPlayer(controller),
              ),
            ),
          ),
          if (_openingFullscreen)
            const Positioned(
              right: 12,
              bottom: 12,
              child: SizedBox.square(
                dimension: 24,
                child: CircularProgressIndicator(
                  color: Colors.white,
                  strokeWidth: 2,
                ),
              ),
            )
          else
            Positioned(
              right: 8,
              bottom: 8,
              child: IconButton.filled(
                tooltip: widget.isApartmentPreview
                    ? 'Open apartment video full screen in landscape'
                    : 'Open room video full screen in landscape',
                onPressed: _openFullscreenVideo,
                style: IconButton.styleFrom(
                  backgroundColor: Colors.black54,
                  foregroundColor: Colors.white,
                ),
                icon: const Icon(Icons.fullscreen),
              ),
            ),
          IconButton.filled(
            onPressed: () {
              setState(() {
                controller.value.isPlaying
                    ? controller.pause()
                    : controller.play();
              });
            },
            style: IconButton.styleFrom(
              backgroundColor: Colors.black54,
              foregroundColor: Colors.white,
            ),
            icon: Icon(
              controller.value.isPlaying ? Icons.pause : Icons.play_arrow,
              size: 34,
            ),
          ),
          Positioned(
            left: 8,
            right: 8,
            bottom: 4,
            child: VideoProgressIndicator(
              controller,
              allowScrubbing: true,
              colors: const VideoProgressColors(
                playedColor: Color(0xFF67C3D0),
                bufferedColor: Colors.white54,
                backgroundColor: Colors.white24,
              ),
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

class _FullscreenRoomVideoPage extends StatefulWidget {
  const _FullscreenRoomVideoPage({
    required this.controller,
    required this.mediaName,
  });

  final VideoPlayerController controller;
  final String mediaName;

  @override
  State<_FullscreenRoomVideoPage> createState() =>
      _FullscreenRoomVideoPageState();
}

class _FullscreenRoomVideoPageState extends State<_FullscreenRoomVideoPage> {
  @override
  Widget build(BuildContext context) {
    final aspectRatio = widget.controller.value.aspectRatio;
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          Center(
            child: AspectRatio(
              aspectRatio: aspectRatio > 0 ? aspectRatio : 16 / 9,
              child: VideoPlayer(widget.controller),
            ),
          ),
          Positioned(
            top: 8,
            right: 8,
            child: SafeArea(
              child: IconButton.filled(
                tooltip: 'Close full-screen video',
                onPressed: () => Navigator.of(context).pop(),
                style: IconButton.styleFrom(
                  backgroundColor: Colors.black54,
                  foregroundColor: Colors.white,
                ),
                icon: const Icon(Icons.close),
              ),
            ),
          ),
          Positioned(
            bottom: 16,
            left: 16,
            right: 16,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                VideoProgressIndicator(
                  widget.controller,
                  allowScrubbing: true,
                  colors: const VideoProgressColors(
                    playedColor: Color(0xFF67C3D0),
                    bufferedColor: Colors.white54,
                    backgroundColor: Colors.white24,
                  ),
                ),
                const SizedBox(height: 12),
                const Padding(
                  padding: EdgeInsets.only(bottom: 12),
                  child: Text(
                    'Rotate your device to landscape for the best view.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white70),
                  ),
                ),
                ValueListenableBuilder<VideoPlayerValue>(
                  valueListenable: widget.controller,
                  builder: (context, value, child) => IconButton.filled(
                    tooltip:
                        '${value.isPlaying ? 'Pause' : 'Play'} ${widget.mediaName} video',
                    onPressed: () => unawaited(
                      value.isPlaying
                          ? widget.controller.pause()
                          : widget.controller.play(),
                    ),
                    style: IconButton.styleFrom(
                      backgroundColor: Colors.black54,
                      foregroundColor: Colors.white,
                    ),
                    icon: Icon(
                      value.isPlaying ? Icons.pause : Icons.play_arrow,
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
            builder: (context, constraints) => _RoomMediaGallery(
              key: ValueKey(room.number),
              room: room,
              aspectRatio: constraints.maxWidth < 600 ? 1.8 : 5.0,
              isApartmentPreview: isApartmentPreview,
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
}

class _HotelPhotoGallery extends StatefulWidget {
  const _HotelPhotoGallery({
    required this.hotel,
    required this.emptyIcon,
    required this.label,
  });

  final Hotel hotel;
  final IconData emptyIcon;
  final String label;

  @override
  State<_HotelPhotoGallery> createState() => _HotelPhotoGalleryState();
}

class _HotelPhotoGalleryState extends State<_HotelPhotoGallery> {
  int _currentPage = 0;

  List<String> get _photoUrls {
    if (widget.hotel.photoUrls.isNotEmpty) return widget.hotel.photoUrls;
    final coverPhotoUrl = widget.hotel.coverPhotoUrl;
    return coverPhotoUrl == null || coverPhotoUrl.isEmpty
        ? const []
        : [coverPhotoUrl];
  }

  @override
  Widget build(BuildContext context) {
    final photoUrls = _photoUrls;
    if (photoUrls.isEmpty) {
      return _PhotoPanel(
        imageUrl: null,
        emptyIcon: widget.emptyIcon,
        label: widget.label,
      );
    }
    return Stack(
      fit: StackFit.expand,
      children: [
        PageView.builder(
          itemCount: photoUrls.length,
          onPageChanged: (index) => setState(() => _currentPage = index),
          itemBuilder: (context, index) => Image.network(
            photoUrls[index],
            fit: BoxFit.cover,
            errorBuilder: (context, error, stackTrace) => _PhotoPanel(
              imageUrl: null,
              emptyIcon: widget.emptyIcon,
              label: widget.label,
            ),
          ),
        ),
        if (photoUrls.length > 1)
          Positioned(
            right: 12,
            top: 12,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.black54,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Text(
                '${_currentPage + 1} / ${photoUrls.length}',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
      ],
    );
  }
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
      const apartmentSteps = [
        'Search shortlet apartments by location, dates and nightly price.',
        'Select an apartment to review its details, photos and video.',
        'Send an availability request to the apartment manager on WhatsApp.',
        'The manager confirms availability and the final price directly with you.',
        'No booking or payment is made through Rooms for shortlet apartments.',
      ];

      return Center(
        child: Container(
          width: double.infinity,
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
                'How Rooms works for apartments',
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 10),
              for (final step in apartmentSteps)
                Padding(
                  padding: const EdgeInsets.only(bottom: 7),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Padding(
                        padding: EdgeInsets.only(top: 7, right: 9),
                        child: Icon(
                          Icons.circle,
                          size: 7,
                          color: Color(0xFF17607A),
                        ),
                      ),
                      Expanded(
                        child: Text(
                          step,
                          style: const TextStyle(
                            color: Color(0xFF596B70),
                            height: 1.45,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
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
