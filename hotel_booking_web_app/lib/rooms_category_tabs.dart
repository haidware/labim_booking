import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

enum RoomsCategoryTab { hotels, apartments, homes, landProperties }

class RoomsCategoryTabs extends StatelessWidget {
  const RoomsCategoryTabs({required this.activeTab, super.key});

  final RoomsCategoryTab activeTab;

  static const _navy = Color(0xFF173651);
  static const _blue = Color(0xFF17607A);
  static const _line = Color(0xFFE3E9EE);

  Future<void> _openTab(BuildContext context, RoomsCategoryTab tab) async {
    final path = switch (tab) {
      RoomsCategoryTab.hotels => '/',
      RoomsCategoryTab.apartments => '/apartment',
      RoomsCategoryTab.homes => '/rental',
      RoomsCategoryTab.landProperties => '/land-properties',
    };
    final opened = await launchUrl(
      Uri.base.resolve(path),
      webOnlyWindowName: '_self',
    );
    if (!opened && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Unable to open that Rooms category.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: _line)),
      ),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Wrap(
            alignment: WrapAlignment.center,
            spacing: 10,
            runSpacing: 8,
            children: [
              _CategoryTab(
                label: 'Hotels',
                selected: activeTab == RoomsCategoryTab.hotels,
                onTap: () => _openTab(context, RoomsCategoryTab.hotels),
              ),
              _CategoryTab(
                label: 'Apartment',
                selected: activeTab == RoomsCategoryTab.apartments,
                onTap: () => _openTab(context, RoomsCategoryTab.apartments),
              ),
              _CategoryTab(
                label: 'Homes',
                selected: activeTab == RoomsCategoryTab.homes,
                onTap: () => _openTab(context, RoomsCategoryTab.homes),
              ),
              _CategoryTab(
                label: 'Land/Properties',
                selected: activeTab == RoomsCategoryTab.landProperties,
                onTap: () => _openTab(context, RoomsCategoryTab.landProperties),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CategoryTab extends StatelessWidget {
  const _CategoryTab({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      child: FilledButton(
        onPressed: onTap,
        style: FilledButton.styleFrom(
          backgroundColor: selected ? RoomsCategoryTabs._blue : Colors.white,
          foregroundColor: selected ? Colors.white : RoomsCategoryTabs._navy,
          side: BorderSide(
            color: selected ? RoomsCategoryTabs._blue : RoomsCategoryTabs._line,
          ),
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
        child: Text(label),
      ),
    );
  }
}
