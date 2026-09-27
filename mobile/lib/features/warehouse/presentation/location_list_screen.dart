import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_spacing.dart';
import '../../../app/theme/app_text_styles.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/loading_view.dart';
import '../../../core/widgets/error_view.dart';
import '../../../core/widgets/empty_view.dart';
import '../../../shared/providers/inventory_providers.dart';
import '../../auth/presentation/auth_provider.dart';

class LocationListScreen extends ConsumerWidget {
  const LocationListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authProvider).user;
    final locationsAsync = ref.watch(locationsFutureProvider);

    return Scaffold(
      backgroundColor: AppColors.canvas,
      appBar: AppBar(
        title: Text('Locations', style: AppTextStyles.headlineLarge),
      ),
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(locationsFutureProvider),
        child: locationsAsync.when(
          loading: () => const LoadingView(message: 'Loading storage locations...'),
          error: (err, _) => ErrorView(
            message: err.toString(),
            onRetry: () => ref.invalidate(locationsFutureProvider),
          ),
          data: (list) {
            if (list.isEmpty) {
              return const EmptyView(
                title: 'No Locations Found',
                subtitle: 'Add storage locations, zones, or racks.',
              );
            }

            return ListView.separated(
              padding: AppSpacing.pagePadding,
              itemCount: list.length,
              separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.sm),
              itemBuilder: (context, i) {
                final loc = list[i] as Map<String, dynamic>;
                final name = loc['name'] as String? ?? 'Location';
                final code = loc['short_code'] as String? ?? 'LOC';
                final isVirtual = (loc['is_virtual'] as bool?) ?? false;

                return AppCard(
                  child: Row(
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: (isVirtual ? AppColors.blueAccent : AppColors.brand).withValues(alpha: 0.1),
                          borderRadius: AppSpacing.borderRadiusMd,
                        ),
                        child: Icon(
                          isVirtual ? Icons.cloud_outlined : Icons.grid_view_rounded,
                          color: isVirtual ? AppColors.blueAccent : AppColors.brand,
                          size: 22,
                        ),
                      ),
                      const SizedBox(width: AppSpacing.md),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(name, style: AppTextStyles.headlineMedium),
                            const SizedBox(height: 2),
                            Text(
                              'Code: $code ${isVirtual ? "• Virtual Zone" : "• Physical Location"}',
                              style: AppTextStyles.bodySmall,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              },
            );
          },
        ),
      ),
      floatingActionButton: (user?.isManager ?? false)
          ? FloatingActionButton.extended(
              backgroundColor: AppColors.brand,
              foregroundColor: Colors.white,
              icon: const Icon(Icons.add_rounded),
              label: const Text('New Location'),
              onPressed: () => context.push('/locations/create'),
            )
          : null,
    );
  }
}
