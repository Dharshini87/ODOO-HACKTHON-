import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_spacing.dart';
import '../../../app/theme/app_text_styles.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/loading_view.dart';
import '../../../shared/providers/inventory_providers.dart';
import '../../auth/presentation/auth_provider.dart';
import 'create_location_screen.dart';

class WarehouseDetailScreen extends ConsumerWidget {
  final Map<String, dynamic> warehouse;

  const WarehouseDetailScreen({super.key, required this.warehouse});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authProvider).user;
    final whId = warehouse['id'] as int? ?? 0;
    final name = warehouse['name'] as String? ?? 'Warehouse';
    final code = warehouse['short_code'] as String? ?? '';
    final address = warehouse['address'] as String? ?? 'No address set';

    final locationsAsync = ref.watch(locationsFutureProvider);

    return Scaffold(
      backgroundColor: AppColors.canvas,
      appBar: AppBar(
        title: Text(name, style: AppTextStyles.headlineLarge),
      ),
      body: ListView(
        padding: AppSpacing.pagePadding,
        children: [
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(name, style: AppTextStyles.headlineLarge),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: AppColors.brandSubtle,
                        borderRadius: AppSpacing.borderRadiusSm,
                      ),
                      child: Text(code, style: AppTextStyles.monoCode.copyWith(color: AppColors.brandDark)),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text('Address: $address', style: AppTextStyles.bodyMedium),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text('Storage Locations in $name', style: AppTextStyles.labelLarge.copyWith(color: AppColors.inkSecondary), overflow: TextOverflow.ellipsis),
              ),
              if (user?.isManager ?? false)
                TextButton.icon(
                  icon: const Icon(Icons.add_rounded, size: 18),
                  label: const Text('Add Location'),
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => CreateLocationScreen(preselectedWarehouseId: whId),
                      ),
                    );
                  },
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          locationsAsync.when(
            loading: () => const LoadingView(message: 'Loading locations...'),
            error: (e, _) => Text('Error loading locations: $e', style: AppTextStyles.bodySmall),
            data: (locs) {
              final whLocs = locs.where((l) => (l['warehouse_id'] as int?) == whId).toList();
              if (whLocs.isEmpty) {
                return const AppCard(
                  child: Center(
                    child: Padding(
                      padding: EdgeInsets.symmetric(vertical: 16.0),
                      child: Text('No storage locations added yet for this warehouse.', style: TextStyle(color: AppColors.inkTertiary)),
                    ),
                  ),
                );
              }
              return Column(
                children: whLocs.map((l) {
                  final locName = l['name'] as String? ?? 'Location';
                  final locCode = l['short_code'] as String? ?? '';
                  final isVirtual = (l['is_virtual'] as bool?) ?? false;

                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8.0),
                    child: AppCard(
                      child: Row(
                        children: [
                          Icon(
                            isVirtual ? Icons.cloud_outlined : Icons.grid_view_rounded,
                            color: AppColors.brand,
                            size: 20,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(locName, style: AppTextStyles.labelLarge),
                                Text('Code: $locCode ${isVirtual ? "• Virtual Location" : ""}', style: AppTextStyles.bodySmall),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }).toList(),
              );
            },
          ),
        ],
      ),
    );
  }
}
