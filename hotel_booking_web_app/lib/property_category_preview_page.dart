import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import 'rooms_category_tabs.dart';

class LandPropertiesPreviewPage extends StatelessWidget {
  const LandPropertiesPreviewPage({super.key});

  static const _listings = [
    _PreviewListing(
      title: 'Residential plot',
      location: 'Kuje, Abuja',
      price: 15000000,
      priceSuffix: 'for sale',
      description: 'Sample residential land with road access.',
      icon: Icons.landscape_rounded,
    ),
    _PreviewListing(
      title: 'Commercial land',
      location: 'Lekki, Lagos',
      price: 1200000,
      priceSuffix: 'per year',
      description: 'Sample commercial plot available for rent.',
      icon: Icons.location_city_rounded,
    ),
    _PreviewListing(
      title: 'Agricultural land',
      location: 'Abeokuta, Ogun',
      price: 9500000,
      priceSuffix: 'for sale',
      description: 'Sample farmland available for purchase.',
      icon: Icons.grass_rounded,
    ),
  ];

  @override
  Widget build(BuildContext context) => const _PropertyCategoryPreviewPage(
    activeTab: RoomsCategoryTab.landProperties,
    title: 'Land and properties',
    subtitle: 'Browse sample land listings for rent or for sale.',
    listings: _listings,
    priceLabel: 'Asking price',
  );
}

class _PropertyCategoryPreviewPage extends StatelessWidget {
  const _PropertyCategoryPreviewPage({
    required this.activeTab,
    required this.title,
    required this.subtitle,
    required this.listings,
    required this.priceLabel,
  });

  final RoomsCategoryTab activeTab;
  final String title;
  final String subtitle;
  final List<_PreviewListing> listings;
  final String priceLabel;

  static const _navy = Color(0xFF173651);
  static const _muted = Color(0xFF6B7B87);
  static const _background = Color(0xFFF6F8FA);
  static final _naira = NumberFormat.currency(
    locale: 'en_NG',
    symbol: '₦',
    decimalDigits: 0,
  );

  Future<void> _goBack(BuildContext context) async {
    final navigator = Navigator.of(context);
    if (navigator.canPop()) {
      navigator.pop();
      return;
    }

    final opened = await launchUrl(
      Uri.base.resolve('/'),
      webOnlyWindowName: '_self',
    );
    if (!opened && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Unable to return to the Rooms homepage.'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _background,
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: _navy,
        leading: IconButton(
          tooltip: 'Back to Rooms home',
          onPressed: () => _goBack(context),
          icon: const Icon(Icons.arrow_back),
        ),
        title: const Text(
          'Rooms',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      body: Column(
        children: [
          RoomsCategoryTabs(activeTab: activeTab),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final columns = constraints.maxWidth >= 1000
                    ? 3
                    : constraints.maxWidth >= 650
                    ? 2
                    : 1;
                return ListView(
                  padding: const EdgeInsets.fromLTRB(18, 26, 18, 40),
                  children: [
                    Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 1100),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            const _PreviewNotice(),
                            const SizedBox(height: 24),
                            Text(
                              title,
                              textAlign: TextAlign.center,
                              style: Theme.of(context).textTheme.headlineLarge
                                  ?.copyWith(
                                    color: _navy,
                                    fontSize: constraints.maxWidth < 500
                                        ? 30
                                        : 40,
                                  ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              subtitle,
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                color: _muted,
                                height: 1.6,
                              ),
                            ),
                            const SizedBox(height: 24),
                            GridView.builder(
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              itemCount: listings.length,
                              gridDelegate:
                                  SliverGridDelegateWithFixedCrossAxisCount(
                                    crossAxisCount: columns,
                                    crossAxisSpacing: 16,
                                    mainAxisSpacing: 16,
                                    mainAxisExtent: 310,
                                  ),
                              itemBuilder: (context, index) => _ListingCard(
                                listing: listings[index],
                                priceLabel: priceLabel,
                                formattedPrice: _naira.format(
                                  listings[index].price,
                                ),
                              ),
                            ),
                            const SizedBox(height: 20),
                            const Text(
                              'Sample listings only. Live inventory, owner contact, and enquiries are not connected yet.',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: _muted,
                                fontSize: 12,
                                height: 1.5,
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
        ],
      ),
    );
  }
}

class _PreviewListing {
  const _PreviewListing({
    required this.title,
    required this.location,
    required this.price,
    required this.priceSuffix,
    required this.description,
    required this.icon,
  });

  final String title;
  final String location;
  final int price;
  final String priceSuffix;
  final String description;
  final IconData icon;
}

class _ListingCard extends StatelessWidget {
  const _ListingCard({
    required this.listing,
    required this.priceLabel,
    required this.formattedPrice,
  });

  final _PreviewListing listing;
  final String priceLabel;
  final String formattedPrice;

  static const _navy = Color(0xFF173651);
  static const _blue = Color(0xFF285F8A);
  static const _muted = Color(0xFF6B7B87);
  static const _line = Color(0xFFE3E9EE);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: _line),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            height: 72,
            width: double.infinity,
            decoration: BoxDecoration(
              color: const Color(0xFFEAF1F5),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(listing.icon, size: 36, color: _blue),
          ),
          const SizedBox(height: 12),
          Text(
            listing.title,
            style: const TextStyle(
              color: _navy,
              fontSize: 17,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(listing.location, style: const TextStyle(color: _muted)),
          const SizedBox(height: 6),
          Text(
            listing.description,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: _muted, height: 1.35),
          ),
          const Spacer(),
          Text(
            '$priceLabel: $formattedPrice ${listing.priceSuffix}',
            style: const TextStyle(color: _navy, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}

class _PreviewNotice extends StatelessWidget {
  const _PreviewNotice();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF5E5),
        border: Border.all(color: const Color(0xFFE9B45F)),
        borderRadius: BorderRadius.circular(14),
      ),
      child: const Text(
        'PREVIEW — sample listings only. These properties are examples; no enquiry or payment is sent or collected.',
        style: TextStyle(
          color: Color(0xFF173651),
          fontWeight: FontWeight.w600,
          height: 1.45,
        ),
      ),
    );
  }
}
