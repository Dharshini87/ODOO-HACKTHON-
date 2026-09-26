import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_spacing.dart';
import '../../../app/theme/app_text_styles.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/loading_view.dart';
import '../../../core/widgets/error_view.dart';
import '../../../core/widgets/empty_view.dart';
import '../../../shared/providers/inventory_providers.dart';
import 'create_warehouse_screen.dart';
import 'warehouse_detail_screen.dart';
import 'location_list_screen.dart';

class WarehouseListScreen extends ConsumerWidget {
  const WarehouseListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final warehousesAsync = ref.watch(warehousesFutureProvider);

    return Scaffold(
      backgroundColor: AppColors.canvas,
      appBar: AppBar(
        title: Text('Warehouses', style: AppTextStyles.headlineLarge),
        actions: [
          IconButton(
            icon: const Icon(Icons.grid_view_rounded),
            tooltip: 'View Storage Locations',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const LocationListScreen()),
              );
            },
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(warehousesFutureProvider),
        child: warehousesAsync.when(
          loading: () => const LoadingView(message: 'Loading warehouses...'),
          error: (err, _) => ErrorView(
            message: err.toString(),
            onRetry: () => ref.invalidate(warehousesFutureProvider),
          ),
          data: (list) {
            if (list.isEmpty) {
              return const EmptyView(
                title: 'No Warehouses Found',
                subtitle: 'Add a new warehouse facility to store inventory.',
              );
            }

            return ListView.separated(
              padding: AppSpacing.pagePadding,
              itemCount: list.length,
              separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.sm),
              itemBuilder: (context, i) {
                final wh = list[i] as Map<String, dynamic>;
                final name = wh['name'] as String? ?? 'Warehouse';
                final code = wh['short_code'] as String? ?? 'WH';
                final address = wh['address'] as String? ?? 'No address set';

                return AppCard(
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => WarehouseDetailScreen(warehouse: wh),
                      ),
                    );
                  },
                  child: Row(
                    children: [
                      Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          color: AppColors.brand.withValues(alpha: 0.1),
                          borderRadius: AppSpacing.borderRadiusMd,
                        ),
                        child: const Icon(Icons.warehouse_rounded, color: AppColors.brand, size: 24),
                      ),
                      const SizedBox(width: AppSpacing.md),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(name, style: AppTextStyles.headlineMedium),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: AppColors.canvas,
                                    borderRadius: AppSpacing.borderRadiusSm,
                                    border: Border.all(color: AppColors.line),
                                  ),
                                  child: Text(code, style: AppTextStyles.monoCode),
                                ),
                              ],
                            ),
                            const SizedBox(height: 2),
                            Text(address, style: AppTextStyles.bodySmall),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      const Icon(Icons.chevron_right_rounded, color: AppColors.inkTertiary),
                    ],
                  ),
                );
              },
            );
          },
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: AppColors.brand,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add_rounded),
        label: const Text('New Warehouse'),
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const CreateWarehouseScreen()),
          );
        },
      ),
    );
  }
}
