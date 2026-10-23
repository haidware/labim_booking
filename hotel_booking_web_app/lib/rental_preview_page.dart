import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'rooms_category_tabs.dart';

class RentalPreviewPage extends StatelessWidget {
  const RentalPreviewPage({super.key});

  static const _navy = Color(0xFF173651);
  static const _blue = Color(0xFF285F8A);
  static const _gold = Color(0xFFE9B45F);
  static const _muted = Color(0xFF6B7B87);
  static const _line = Color(0xFFE3E9EE);
  static const _background = Color(0xFFF6F8FA);
  static final _naira = NumberFormat.currency(
    locale: 'en_NG',
    symbol: '₦',
    decimalDigits: 0,
  );

  static const _listings = [
    _RentalListing(
      title: 'Bright 2-bedroom terrace',
      location: 'Gwarinpa, Abuja',
      rent: 2400000,
      bedrooms: 2,
      bathrooms: 2,
      imageUrl:
          'https://images.unsplash.com/photo-1600596542815-ffad4c1539a9?auto=format&fit=crop&w=1200&q=85',
      description:
          'A sample family home with a fitted kitchen, secure parking and a private outdoor space.',
    ),
    _RentalListing(
      title: 'Modern 3-bedroom apartment',
      location: 'Lekki Phase 1, Lagos',
      rent: 4800000,
      bedrooms: 3,
      bathrooms: 3,
      imageUrl:
          'https://images.unsplash.com/photo-1600607687939-ce8a6c25118c?auto=format&fit=crop&w=1200&q=85',
      description:
          'A sample apartment with spacious rooms, natural light and shared building security.',
    ),
    _RentalListing(
      title: 'Quiet 1-bedroom flat',
      location: 'Bodija, Ibadan',
      rent: 900000,
      bedrooms: 1,
      bathrooms: 1,
      imageUrl:
          'https://images.unsplash.com/photo-1600210492486-724fe5c67fb0?auto=format&fit=crop&w=1200&q=85',
      description:
          'A sample one-bedroom flat close to local shops and public transport.',
    ),
  ];

  Future<void> _showInspectionFlow(
    BuildContext context,
    _RentalListing listing,
  ) async {
    var preference = 'In-person viewing';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Preview an inspection request'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(listing.title),
              const SizedBox(height: 18),
              const Text('How would you like to view this property?'),
              const SizedBox(height: 8),
              RadioGroup<String>(
                groupValue: preference,
                onChanged: (value) {
                  if (value != null) {
                    setDialogState(() => preference = value);
                  }
                },
                child: Column(
                  children: [
                    for (final option in [
                      'In-person viewing',
                      'Virtual viewing',
                    ])
                      RadioListTile<String>(
                        contentPadding: EdgeInsets.zero,
                        title: Text(option),
                        value: option,
                      ),
                  ],
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Continue'),
            ),
          ],
        ),
      ),
    );
    if (confirmed != true || !context.mounted) return;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        icon: const Icon(Icons.visibility_outlined, color: _blue),
        title: const Text('Inspection preview complete'),
        content: Text(
          '$preference selected for ${listing.title}. '
          'This is a mockup only: no request was sent, and no payment was collected.',
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Done'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _background,
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: _navy,
        title: const Text(
          'Rooms',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      body: Column(
        children: [
          const RoomsCategoryTabs(activeTab: RoomsCategoryTab.homes),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final columns = constraints.maxWidth >= 1000
                    ? 3
                    : constraints.maxWidth >= 650
                    ? 2
                    : 1;
                return ListView(
                  padding: const EdgeInsets.fromLTRB(18, 28, 18, 40),
                  children: [
                    Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 1100),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            const _PreviewNotice(),
                            const SizedBox(height: 25),
                            Text(
                              'Find a place to call home',
                              textAlign: TextAlign.center,
                              style: Theme.of(context).textTheme.headlineLarge
                                  ?.copyWith(
                                    color: _navy,
                                    fontSize: constraints.maxWidth < 500
                                        ? 30
                                        : 40,
                                  ),
                            ),
                            const SizedBox(height: 10),
                            const Text(
                              'Explore sample homes and preview how an inspection request will work.',
                              textAlign: TextAlign.center,
                              style: TextStyle(color: _muted, height: 1.6),
                            ),
                            const SizedBox(height: 25),
                            GridView.builder(
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              itemCount: _listings.length,
                              gridDelegate:
                                  SliverGridDelegateWithFixedCrossAxisCount(
                                    crossAxisCount: columns,
                                    crossAxisSpacing: 18,
                                    mainAxisSpacing: 18,
                                    mainAxisExtent: 490,
                                  ),
                              itemBuilder: (context, index) => _RentalCard(
                                listing: _listings[index],
                                rentLabel: _naira.format(_listings[index].rent),
                                onInspect: () => _showInspectionFlow(
                                  context,
                                  _listings[index],
                                ),
                              ),
                            ),
                            const SizedBox(height: 24),
                            const Text(
                              'Preview listings are examples only. Live property data, owner contact, '
                              'and inspection requests will be connected later.',
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

class _RentalListing {
  const _RentalListing({
    required this.title,
    required this.location,
    required this.rent,
    required this.bedrooms,
    required this.bathrooms,
    required this.imageUrl,
    required this.description,
  });

  final String title;
  final String location;
  final int rent;
  final int bedrooms;
  final int bathrooms;
  final String imageUrl;
  final String description;
}

class _PreviewNotice extends StatelessWidget {
  const _PreviewNotice();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF5E5),
        border: Border.all(color: const Color(0xFFE9B45F)),
        borderRadius: BorderRadius.circular(14),
      ),
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline, color: RentalPreviewPage._navy),
          SizedBox(width: 11),
          Expanded(
            child: Text(
              'MOCKUP — sample listings only. Inspection choices are simulated; '
              'nothing is sent and no rent or fee is collected.',
              style: TextStyle(
                color: RentalPreviewPage._navy,
                fontWeight: FontWeight.w600,
                height: 1.45,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RentalCard extends StatelessWidget {
  const _RentalCard({
    required this.listing,
    required this.rentLabel,
    required this.onInspect,
  });

  final _RentalListing listing;
  final String rentLabel;
  final VoidCallback onInspect;

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      color: Colors.white,
      elevation: 0,
      shape: RoundedRectangleBorder(
        side: const BorderSide(color: RentalPreviewPage._line),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: 190,
            child: Stack(
              fit: StackFit.expand,
              children: [
                Image.network(
                  listing.imageUrl,
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) =>
                      const ColoredBox(
                        color: Color(0xFFDDE6EC),
                        child: Icon(
                          Icons.home_outlined,
                          size: 48,
                          color: RentalPreviewPage._blue,
                        ),
                      ),
                ),
                Positioned(
                  top: 12,
                  left: 12,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: RentalPreviewPage._gold,
                      borderRadius: BorderRadius.circular(7),
                    ),
                    child: const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 9, vertical: 6),
                      child: Text(
                        'SAMPLE LISTING',
                        style: TextStyle(
                          color: RentalPreviewPage._navy,
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(15),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    listing.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: RentalPreviewPage._navy,
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    listing.location,
                    style: const TextStyle(color: RentalPreviewPage._muted),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    '$rentLabel / year',
                    style: const TextStyle(
                      color: RentalPreviewPage._blue,
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 7),
                  Text(
                    '${listing.bedrooms} bedrooms  ·  ${listing.bathrooms} bathrooms',
                    style: const TextStyle(
                      color: RentalPreviewPage._muted,
                      fontSize: 12,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    listing.description,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: RentalPreviewPage._muted,
                      fontSize: 12,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: onInspect,
                      style: FilledButton.styleFrom(
                        backgroundColor: RentalPreviewPage._navy,
                      ),
                      child: const Text('Preview inspection'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
