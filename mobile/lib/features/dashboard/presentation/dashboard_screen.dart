import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_spacing.dart';
import '../../../app/theme/app_text_styles.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/status_badge.dart';
import '../../../core/widgets/loading_view.dart';
import '../../../core/widgets/error_view.dart';
import '../../../shared/providers/inventory_providers.dart';
import '../../auth/presentation/auth_provider.dart';
import '../../intelligence/presentation/intelligence_screen.dart';

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  Widget _buildMetricTile({
    required BuildContext context,
    required String title,
    required String value,
    required IconData icon,
    required Color tone,
    String? subtitle,
    VoidCallback? onTap,
  }) {
    return AppCard(
      onTap: onTap,
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: tone.withValues(alpha: 0.12),
              borderRadius: AppSpacing.borderRadiusMd,
            ),
            child: Icon(icon, color: tone, size: 22),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  value,
                  style: AppTextStyles.headlineLarge.copyWith(fontWeight: FontWeight.w700),
                ),
                Text(
                  title,
                  style: AppTextStyles.bodySmall.copyWith(color: AppColors.inkSecondary),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: AppTextStyles.labelSmall.copyWith(color: tone, fontWeight: FontWeight.w600),
                  ),
                ],
              ],
            ),
          ),
          const Icon(Icons.chevron_right_rounded, color: AppColors.inkTertiary, size: 20),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dashboardAsync = ref.watch(dashboardFutureProvider);
    final user = ref.watch(authProvider).user;

    return Scaffold(
      backgroundColor: AppColors.canvas,
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('StockSense', style: AppTextStyles.headlineLarge),
            Text(
              'Hello, ${user?.name ?? 'Warehouse Staff'} • ${user?.role.replaceAll("_", " ") ?? "STAFF"}',
              style: AppTextStyles.bodySmall.copyWith(color: AppColors.inkSecondary),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Settings & Profile',
            icon: const Icon(Icons.account_circle_outlined),
            onPressed: () => context.go('/more'),
          ),
        ],
      ),
      body: RefreshIndicator(
        color: AppColors.brand,
        onRefresh: () async {
          ref.invalidate(dashboardFutureProvider);
          await ref.read(dashboardFutureProvider.future);
        },
        child: dashboardAsync.when(
          loading: () => const LoadingView(message: 'Loading database metrics...'),
          error: (err, stack) => ErrorView(
            message: err.toString(),
            onRetry: () => ref.invalidate(dashboardFutureProvider),
          ),
          data: (data) => ListView(
            padding: AppSpacing.pagePadding,
            children: [
              // Hero Quick Actions
              Row(
                children: [
                  Expanded(
                    child: AppCard(
                      color: AppColors.charcoal,
                      border: BorderSide.none,
                      onTap: () => context.push('/receipts'),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: AppColors.amber.withValues(alpha: 0.2),
                              borderRadius: AppSpacing.borderRadiusSm,
                            ),
                            child: const Icon(Icons.arrow_downward_rounded, color: AppColors.amber, size: 20),
                          ),
                          const SizedBox(height: AppSpacing.md),
                          Text(
                            'Receipts',
                            style: AppTextStyles.headlineMedium.copyWith(color: Colors.white),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Log incoming stock',
                            style: AppTextStyles.bodySmall.copyWith(color: Colors.white70),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: AppCard(
                      color: AppColors.brand,
                      border: BorderSide.none,
                      onTap: () => context.push('/deliveries'),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.2),
                              borderRadius: AppSpacing.borderRadiusSm,
                            ),
                            child: const Icon(Icons.arrow_upward_rounded, color: Colors.white, size: 20),
                          ),
                          const SizedBox(height: AppSpacing.md),
                          Text(
                            'Deliveries',
                            style: AppTextStyles.headlineMedium.copyWith(color: Colors.white),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Dispatch orders',
                            style: AppTextStyles.bodySmall.copyWith(color: Colors.white70),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.lg),

              // SECTION 26 CORE DISPLAY METRICS
              Text('Live Inventory Metrics', style: AppTextStyles.headlineMedium),
              const SizedBox(height: AppSpacing.sm),

              // Total Stock Hero Card
              AppCard(
                color: AppColors.panel,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('TOTAL STOCK', style: AppTextStyles.labelSmall.copyWith(letterSpacing: 1.1)),
                        const SizedBox(height: 4),
                        Text(
                          '${data.totalStock.toInt()}',
                          style: AppTextStyles.displaySmall.copyWith(color: AppColors.brand, fontWeight: FontWeight.w800),
                        ),
                        Text('units across all locations', style: AppTextStyles.labelSmall.copyWith(color: AppColors.inkTertiary)),
                      ],
                    ),
                    Container(
                      width: 54,
                      height: 54,
                      decoration: BoxDecoration(
                        color: AppColors.brand.withValues(alpha: 0.12),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.warehouse_rounded, color: AppColors.brand, size: 28),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.sm),

              // Low Stock & Out of Stock Cards
              Row(
                children: [
                  Expanded(
                    child: AppCard(
                      onTap: () => context.go('/stock'),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Icon(Icons.warning_amber_rounded, color: AppColors.statusWaiting, size: 22),
                              Text('${data.lowStockCount}', style: AppTextStyles.headlineLarge.copyWith(color: AppColors.statusWaiting)),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Text('Low Stock', style: AppTextStyles.labelLarge),
                          Text('Needs reorder', style: AppTextStyles.labelSmall.copyWith(color: AppColors.inkTertiary)),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: AppCard(
                      onTap: () => context.go('/stock'),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Icon(Icons.cancel_outlined, color: AppColors.statusCancelled, size: 22),
                              Text('${data.outOfStockCount}', style: AppTextStyles.headlineLarge.copyWith(color: AppColors.statusCancelled)),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Text('Out of Stock', style: AppTextStyles.labelLarge),
                          Text('0 units on hand', style: AppTextStyles.labelSmall.copyWith(color: AppColors.inkTertiary)),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),

              // Operations Section Header & KPIs
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Operations', style: AppTextStyles.headlineMedium),
                  TextButton.icon(
                    onPressed: () => context.go('/operations'),
                    icon: const Icon(Icons.dashboard_outlined, size: 16),
                    label: const Text('Operator Dashboard'),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.xs),

              // Operations KPIs (Pending Receipts, Deliveries, Waiting Deliveries, Transfers)
              _buildMetricTile(
                context: context,
                title: 'Pending Receipts',
                value: '${data.pendingReceipts}',
                icon: Icons.move_to_inbox_rounded,
                tone: AppColors.statusReady,
                onTap: () => context.push('/receipts'),
              ),
              const SizedBox(height: AppSpacing.sm),
              _buildMetricTile(
                context: context,
                title: 'Pending Deliveries',
                value: '${data.pendingDeliveries}',
                icon: Icons.local_shipping_outlined,
                tone: AppColors.brand,
                subtitle: data.waitingDeliveries > 0 ? '${data.waitingDeliveries} waiting for stock' : null,
                onTap: () => context.push('/deliveries'),
              ),
              const SizedBox(height: AppSpacing.sm),
              _buildMetricTile(
                context: context,
                title: 'Waiting Deliveries',
                value: '${data.waitingDeliveries}',
                icon: Icons.hourglass_top_rounded,
                tone: AppColors.amber,
                subtitle: 'Deliveries with stock shortage',
                onTap: () => context.push('/deliveries'),
              ),
              const SizedBox(height: AppSpacing.sm),
              _buildMetricTile(
                context: context,
                title: 'Transfers Scheduled',
                value: '${data.transfersScheduled}',
                icon: Icons.swap_horiz_rounded,
                tone: AppColors.charcoal,
                onTap: () => context.push('/transfers'),
              ),
              const SizedBox(height: AppSpacing.lg),

              // SECTION 26 & 27: LOW STOCK PRODUCTS (SHOWING ON HAND, RESERVED, FREE TO USE)
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Low Stock Products', style: AppTextStyles.headlineMedium),
                  TextButton(
                    onPressed: () => context.go('/stock'),
                    child: const Text('View All'),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.xs),

              if (data.lowStockProducts.isEmpty)
                Container(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  decoration: BoxDecoration(
                    color: AppColors.statusDone.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.statusDone.withValues(alpha: 0.3)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.check_circle_rounded, color: AppColors.statusDone),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Healthy stock levels! No products are currently below reorder threshold.',
                          style: AppTextStyles.bodySmall.copyWith(color: AppColors.statusDone, fontWeight: FontWeight.w600),
                        ),
                      ),
                    ],
                  ),
                )
              else
                ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: data.lowStockProducts.take(5).length,
                  separatorBuilder: (context, index) => const SizedBox(height: AppSpacing.sm),
                  itemBuilder: (context, index) {
                    final item = data.lowStockProducts[index];
                    final isOutOfStock = item.status == 'OUT OF STOCK';

                    return AppCard(
                      onTap: () => context.go('/stock'),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Expanded(
                                child: Text(
                                  item.productName,
                                  style: AppTextStyles.headlineMedium,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: isOutOfStock
                                      ? AppColors.statusCancelled.withValues(alpha: 0.12)
                                      : AppColors.statusWaiting.withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(
                                    color: isOutOfStock ? AppColors.statusCancelled : AppColors.statusWaiting,
                                    width: 1,
                                  ),
                                ),
                                child: Text(
                                  item.status,
                                  style: AppTextStyles.labelSmall.copyWith(
                                    color: isOutOfStock ? AppColors.statusCancelled : AppColors.statusWaiting,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 2),
                          Text('SKU: ${item.sku} • Reorder Level: ${item.reorderLevel.toInt()}', style: AppTextStyles.bodySmall),
                          const Divider(height: 16),
                          // Section 27 Quantities: On Hand, Reserved, Free to Use
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceAround,
                            children: [
                              Column(
                                children: [
                                  Text('ON HAND', style: AppTextStyles.labelSmall),
                                  const SizedBox(height: 2),
                                  Text(
                                    '${item.onHand.toInt()}',
                                    style: AppTextStyles.headlineSmall.copyWith(
                                      color: isOutOfStock ? AppColors.statusCancelled : AppColors.ink,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ],
                              ),
                              Column(
                                children: [
                                  Text('RESERVED', style: AppTextStyles.labelSmall),
                                  const SizedBox(height: 2),
                                  Text(
                                    '${item.reserved.toInt()}',
                                    style: AppTextStyles.headlineSmall.copyWith(
                                      color: AppColors.statusWaiting,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ],
                              ),
                              Column(
                                children: [
                                  Text('FREE TO USE', style: AppTextStyles.labelSmall),
                                  const SizedBox(height: 2),
                                  Text(
                                    '${item.freeToUse.toInt()}',
                                    style: AppTextStyles.headlineSmall.copyWith(
                                      color: AppColors.brand,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ],
                      ),
                    );
                  },
                ),
              const SizedBox(height: AppSpacing.lg),

              // INVENTORY INTELLIGENCE PREVIEW (Section 26 & 28)
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Inventory Intelligence', style: AppTextStyles.headlineMedium),
                  TextButton(
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const IntelligenceScreen()),
                    ),
                    child: const Text('View Analytics'),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              AppCard(
                color: AppColors.brand.withValues(alpha: 0.05),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const IntelligenceScreen()),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.insights_rounded, color: AppColors.brand, size: 22),
                            const SizedBox(width: 8),
                            Text('Valuation & Turnover', style: AppTextStyles.headlineMedium.copyWith(color: AppColors.brand)),
                          ],
                        ),
                        const Icon(Icons.chevron_right_rounded, color: AppColors.brand, size: 20),
                      ],
                    ),
                    const Divider(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('Total Stock Value', style: AppTextStyles.bodySmall),
                        Text(
                          '\$${data.intelligence.totalStockValue.toStringAsFixed(2)}',
                          style: AppTextStyles.headlineMedium.copyWith(fontWeight: FontWeight.w700),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('Dead Stock (Inactive)', style: AppTextStyles.bodySmall),
                        Text(
                          '${data.intelligence.deadStockCount} items',
                          style: AppTextStyles.bodySmall.copyWith(fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('Reorder Recommendations', style: AppTextStyles.bodySmall),
                        Text(
                          '${data.intelligence.reorderRecommendedCount} items',
                          style: AppTextStyles.bodySmall.copyWith(
                            color: data.intelligence.reorderRecommendedCount > 0 ? AppColors.statusWaiting : AppColors.statusDone,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                    if (data.intelligence.fastMovingItems.isNotEmpty) ...[
                      const Divider(height: 16),
                      Text('Fast Moving Products:', style: AppTextStyles.labelSmall),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: data.intelligence.fastMovingItems.map((name) {
                          return Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: AppColors.panel,
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(color: AppColors.line),
                            ),
                            child: Text(name, style: AppTextStyles.labelSmall.copyWith(color: AppColors.ink)),
                          );
                        }).toList(),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.lg),

              // RECENT MOVEMENTS (Section 26)
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Recent Movements', style: AppTextStyles.headlineMedium),
                  TextButton(
                    onPressed: () => context.go('/history'),
                    child: const Text('View All'),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.xs),

              if (data.recentMovements.isEmpty)
                const AppCard(
                  child: Center(
                    child: Padding(
                      padding: EdgeInsets.all(AppSpacing.md),
                      child: Text('No transactions recorded yet.'),
                    ),
                  ),
                )
              else
                ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: data.recentMovements.take(5).length,
                  separatorBuilder: (context, index) => const SizedBox(height: AppSpacing.sm),
                  itemBuilder: (context, index) {
                    final move = data.recentMovements[index];
                    return AppCard(
                      onTap: () {
                        if (move.type == 'RECEIPT') {
                          context.push('/receipts');
                        } else if (move.type == 'DELIVERY') {
                          context.push('/deliveries');
                        } else if (move.type == 'TRANSFER') {
                          context.push('/transfers');
                        } else {
                          context.push('/adjustments');
                        }
                      },
                      child: Row(
                        children: [
                          Container(
                            width: 38,
                            height: 38,
                            decoration: BoxDecoration(
                              color: AppColors.panel,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: AppColors.line),
                            ),
                            child: Icon(
                              move.type == 'RECEIPT'
                                  ? Icons.arrow_downward_rounded
                                  : (move.type == 'DELIVERY'
                                      ? Icons.arrow_upward_rounded
                                      : (move.type == 'TRANSFER'
                                          ? Icons.swap_horiz_rounded
                                          : Icons.tune_rounded)),
                              size: 18,
                              color: AppColors.ink,
                            ),
                          ),
                          const SizedBox(width: AppSpacing.md),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(move.reference, style: AppTextStyles.monoCode.copyWith(fontWeight: FontWeight.w700)),
                                    StatusBadge(status: move.status),
                                  ],
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  '${move.productName} • ${move.quantity.toInt()} units',
                                  style: AppTextStyles.bodySmall.copyWith(color: AppColors.ink, fontWeight: FontWeight.w600),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              const SizedBox(height: AppSpacing.xxl),
            ],
          ),
        ),
      ),
    );
  }
}
