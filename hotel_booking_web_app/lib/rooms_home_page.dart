import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

class RoomsHomePage extends StatefulWidget {
  const RoomsHomePage({super.key});

  @override
  State<RoomsHomePage> createState() => _RoomsHomePageState();
}

class _RoomsHomePageState extends State<RoomsHomePage> {
  static const _navy = Color(0xFF173651);
  static const _blue = Color(0xFF285F8A);
  static const _gold = Color(0xFFE9B45F);
  static const _muted = Color(0xFF6B7B87);
  static const _line = Color(0xFFE3E9EE);
  static const _background = Color(0xFFF6F8FA);

  Future<void> _openBooking() async {
    final bookingUri = Uri.base.resolve('/book');
    final opened = await launchUrl(bookingUri, webOnlyWindowName: '_blank');
    if (!opened && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Unable to open the hotel booking page.')),
      );
    }
  }

  Future<void> _openRentals() async {
    final opened = await launchUrl(
      Uri.base.resolve('/rental'),
      webOnlyWindowName: '_self',
    );
    if (!opened && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Unable to open house rentals.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _background,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final isMobile = constraints.maxWidth <= 640;
            return Column(
              children: [
                _buildHeader(isMobile),
                Expanded(
                  child: SingleChildScrollView(
                    child: Column(
                      children: [
                        Padding(
                          padding: EdgeInsets.fromLTRB(
                            18,
                            isMobile ? 37 : 55,
                            18,
                            isMobile ? 45 : 68,
                          ),
                          child: Center(
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 980),
                              child: Column(
                                children: [
                                  _Intro(isMobile: isMobile),
                                  SizedBox(height: isMobile ? 25 : 34),
                                  ConstrainedBox(
                                    constraints: BoxConstraints(
                                      maxWidth: isMobile ? 430 : 850,
                                    ),
                                    child: isMobile
                                        ? Column(
                                            children: [
                                              _HotelChoice(
                                                onTap: _openBooking,
                                                compact: true,
                                              ),
                                              const SizedBox(height: 18),
                                              _RentChoice(
                                                onTap: _openRentals,
                                                compact: true,
                                              ),
                                            ],
                                          )
                                        : Row(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Expanded(
                                                child: _HotelChoice(
                                                  onTap: _openBooking,
                                                ),
                                              ),
                                              const SizedBox(width: 25),
                                              Expanded(
                                                child: _RentChoice(
                                                  onTap: _openRentals,
                                                ),
                                              ),
                                            ],
                                          ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(19),
                          decoration: const BoxDecoration(
                            color: Colors.white,
                            border: Border(top: BorderSide(color: _line)),
                          ),
                          child: const Text(
                            'Rooms · Hotel bookings and a house-rental preview',
                            textAlign: TextAlign.center,
                            style: TextStyle(fontSize: 12, color: _muted),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildHeader(bool isMobile) {
    return Container(
      height: isMobile ? 72 : 82,
      width: double.infinity,
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: _line)),
      ),
      child: Center(
        child: Semantics(
          label: 'Rooms homepage',
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                height: isMobile ? 38 : 42,
                width: isMobile ? 38 : 42,
                decoration: BoxDecoration(
                  color: _gold,
                  borderRadius: BorderRadius.circular(12),
                ),
                alignment: Alignment.center,
                child: const Text(
                  '⌂',
                  style: TextStyle(fontSize: 26, color: _navy),
                ),
              ),
              const SizedBox(width: 10),
              RichText(
                text: TextSpan(
                  style: TextStyle(
                    color: _navy,
                    fontSize: isMobile ? 27 : 30,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -1.2,
                  ),
                  children: const [
                    TextSpan(text: 'Rooms'),
                    TextSpan(
                      text: '.',
                      style: TextStyle(color: _blue),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Intro extends StatelessWidget {
  const _Intro({required this.isMobile});

  final bool isMobile;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const Text(
          'YOUR NEXT PLACE STARTS HERE',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: _RoomsHomePageState._blue,
            fontSize: 11,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.8,
          ),
        ),
        const SizedBox(height: 11),
        Text(
          'What are you looking for?',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.headlineLarge?.copyWith(
            color: _RoomsHomePageState._navy,
            fontSize: isMobile ? 30 : 42,
            letterSpacing: -1.3,
            height: 1.12,
          ),
        ),
        const SizedBox(height: 10),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Text(
            'Book available hotel rooms or preview homes for rent.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: _RoomsHomePageState._muted,
              fontSize: 15,
              height: 1.7,
            ),
          ),
        ),
      ],
    );
  }
}

class _HotelChoice extends StatelessWidget {
  const _HotelChoice({required this.onTap, this.compact = false});

  final VoidCallback onTap;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return _ChoiceCard(
      onTap: onTap,
      compact: compact,
      imageUrl:
          'https://images.unsplash.com/photo-1566073771259-6a8506099945?auto=format&fit=crop&w=1000&q=85',
      number: '01 · HOTEL STAYS',
      icon: '🛎️',
      title: 'Hotel',
      description:
          'See live available rooms, check prices and book your hotel stay online.',
      buttonText: 'Book Hotel',
      buttonColor: _RoomsHomePageState._navy,
      buttonTextColor: Colors.white,
      arrow: '↗',
      microcopy: 'Live availability through our booking app',
    );
  }
}

class _RentChoice extends StatelessWidget {
  const _RentChoice({required this.onTap, this.compact = false});

  final VoidCallback onTap;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return _ChoiceCard(
      onTap: onTap,
      compact: compact,
      imageUrl:
          'https://images.unsplash.com/photo-1600607687939-ce8a6c25118c?auto=format&fit=crop&w=1000&q=85',
      number: '02 · RENT A HOME',
      icon: '🏡',
      title: 'Rent House',
      description:
          'Explore houses and flats, then preview how to request a property inspection.',
      buttonText: 'Rent House',
      buttonColor: _RoomsHomePageState._gold,
      buttonTextColor: const Color(0xFF1D2D3B),
      arrow: '→',
      microcopy: 'Rental listings preview only',
    );
  }
}

class _ChoiceCard extends StatelessWidget {
  const _ChoiceCard({
    required this.onTap,
    required this.compact,
    required this.imageUrl,
    required this.number,
    required this.icon,
    required this.title,
    required this.description,
    required this.buttonText,
    required this.buttonColor,
    required this.buttonTextColor,
    required this.arrow,
    required this.microcopy,
  });

  final VoidCallback onTap;
  final bool compact;
  final String imageUrl;
  final String number;
  final String icon;
  final String title;
  final String description;
  final String buttonText;
  final Color buttonColor;
  final Color buttonTextColor;
  final String arrow;
  final String microcopy;

  @override
  Widget build(BuildContext context) {
    final imageHeight = compact ? 205.0 : 235.0;
    return Semantics(
      button: true,
      label: '$buttonText. $description',
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Container(
            decoration: BoxDecoration(
              border: Border.all(color: _RoomsHomePageState._line),
              borderRadius: BorderRadius.circular(18),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x0E143046),
                  blurRadius: 24,
                  offset: Offset(0, 8),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  height: imageHeight,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      Image.network(
                        imageUrl,
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) => Container(
                          color: const Color(0xFFDDE6EC),
                          alignment: Alignment.center,
                          child: const Icon(
                            Icons.image_outlined,
                            color: _RoomsHomePageState._blue,
                            size: 42,
                          ),
                        ),
                      ),
                      const DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.bottomCenter,
                            end: Alignment.topCenter,
                            colors: [Color(0x800A1D2E), Color(0x000A1D2E)],
                            stops: [0, .58],
                          ),
                        ),
                      ),
                      Positioned(
                        top: 15,
                        left: 15,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 7,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xF2FFFFFF),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            number,
                            style: const TextStyle(
                              color: _RoomsHomePageState._navy,
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(21, 0, 21, 21),
                  child: Column(
                    children: [
                      SizedBox(
                        height: 27,
                        child: Transform.translate(
                          offset: const Offset(0, -25),
                          child: Container(
                            height: 52,
                            width: 52,
                            decoration: BoxDecoration(
                              color: const Color(0xFFEDF3F7),
                              border: Border.all(color: Colors.white, width: 4),
                              borderRadius: BorderRadius.circular(15),
                            ),
                            alignment: Alignment.center,
                            child: Text(
                              icon,
                              style: const TextStyle(fontSize: 27),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),
                      Text(
                        title,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: _RoomsHomePageState._navy,
                          fontSize: 25,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -.7,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        description,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: _RoomsHomePageState._muted,
                          fontSize: 14,
                          height: 1.65,
                        ),
                      ),
                      const SizedBox(height: 21),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(
                          vertical: 14,
                          horizontal: 19,
                        ),
                        decoration: BoxDecoration(
                          color: buttonColor,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              buttonText,
                              style: TextStyle(
                                color: buttonTextColor,
                                fontSize: 14,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(width: 9),
                            Text(
                              arrow,
                              style: TextStyle(
                                color: buttonTextColor,
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 13),
                      Text(
                        microcopy,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: _RoomsHomePageState._muted,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
