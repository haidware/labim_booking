import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

enum RoomsCategoryTab { hotels, apartments, homes, landProperties }

class RoomsCategoryTabs extends StatelessWidget {
  const RoomsCategoryTabs({required this.activeTab, super.key});

  final RoomsCategoryTab activeTab;

  static const _navy = Color(0xFF485B60);
  static const _blue = Color(0xFF1B6578);
  static const _tileBackground = Color(0xFFF1F6F6);

  Future<void> _openTab(BuildContext context, RoomsCategoryTab tab) async {
    final path = switch (tab) {
      RoomsCategoryTab.hotels => '/',
      RoomsCategoryTab.apartments => '/apartment',
      RoomsCategoryTab.homes => '/rentals',
      RoomsCategoryTab.landProperties => '/rentals/land',
    };
    final uri = Uri.parse(path);
    final opened = await launchUrl(
      uri.hasScheme ? uri : Uri.base.resolve(path),
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
    return SizedBox(
      width: double.infinity,
      child: Row(
        children: [
          Expanded(
            child: _CategoryTab(
              icon: Icons.bed_outlined,
              label: 'Hotels',
              selected: activeTab == RoomsCategoryTab.hotels,
              onTap: () => _openTab(context, RoomsCategoryTab.hotels),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _CategoryTab(
              icon: Icons.apartment_outlined,
              label: 'Apartment',
              selected: activeTab == RoomsCategoryTab.apartments,
              onTap: () => _openTab(context, RoomsCategoryTab.apartments),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _CategoryTab(
              icon: Icons.home_outlined,
              label: 'Homes',
              selected: activeTab == RoomsCategoryTab.homes,
              onTap: () => _openTab(context, RoomsCategoryTab.homes),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _CategoryTab(
              icon: Icons.map_outlined,
              label: 'Land/Properties',
              selected: activeTab == RoomsCategoryTab.landProperties,
              onTap: () => _openTab(context, RoomsCategoryTab.landProperties),
            ),
          ),
        ],
      ),
    );
  }
}

class _CategoryTab extends StatelessWidget {
  const _CategoryTab({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 120;
          return Material(
            color: selected
                ? RoomsCategoryTabs._blue
                : RoomsCategoryTabs._tileBackground,
            borderRadius: BorderRadius.circular(compact ? 14 : 18),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: onTap,
              child: SizedBox(
                height: compact ? 72 : 88,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 2,
                    vertical: 8,
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        icon,
                        size: compact ? 19 : 23,
                        color: selected
                            ? Colors.white
                            : RoomsCategoryTabs._navy,
                      ),
                      const SizedBox(height: 5),
                      Text(
                        label,
                        textAlign: TextAlign.center,
                        maxLines: 2,
                        style: TextStyle(
                          color: selected
                              ? Colors.white
                              : RoomsCategoryTabs._navy,
                          fontSize: compact ? 10 : 14,
                          height: 1.1,
                          fontWeight: selected
                              ? FontWeight.w600
                              : FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
