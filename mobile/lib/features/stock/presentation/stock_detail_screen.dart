import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_spacing.dart';
import '../../../app/theme/app_text_styles.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/status_badge.dart';
import '../../../core/widgets/loading_view.dart';
import '../../../shared/providers/inventory_providers.dart';
import '../../auth/presentation/auth_provider.dart';
import 'product_detail_screen.dart';

class StockDetailScreen extends ConsumerWidget {
  final StockItem item;

  const StockDetailScreen({super.key, required this.item});

  Widget _buildMetricTile(String label, String value, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: AppSpacing.borderRadiusSm,
          border: Border.all(color: color.withValues(alpha: 0.2)),
        ),
        child: Column(
          children: [
            Text(
              label,
              style: AppTextStyles.labelSmall.copyWith(
                color: color,
                fontSize: 10,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.5,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 4),
            Text(
              value,
              style: AppTextStyles.headlineMedium.copyWith(
                color: color,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authProvider).user;
    final historyAsync = ref.watch(moveHistoryFutureProvider);
    final uom = item.unitOfMeasure;

    return Scaffold(
      backgroundColor: AppColors.canvas,
      appBar: AppBar(
        title: Text(item.productName, style: AppTextStyles.headlineLarge),
        actions: [
          if (user?.isManager ?? false)
            IconButton(
              icon: const Icon(Icons.edit_outlined),
              tooltip: 'Edit Product',
              onPressed: () {
                final prods = ref.read(productsFutureProvider).asData?.value ?? [];
                final prod = prods.firstWhere(
                  (p) => (p['id'] == item.productId) || (p['sku'] == item.sku),
                  orElse: () => {
                    'id': item.productId,
                    'name': item.productName,
                    'sku': item.sku,
                    'unit_of_measure': item.unitOfMeasure,
                    'unit_cost': item.costPerUnit,
                    'reorder_point': item.reorderPoint,
                    'is_active': true,
                  },
                );
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => ProductDetailScreen(product: Map<String, dynamic>.from(prod as Map)),
                  ),
                );
              },
            ),
          Padding(
            padding: const EdgeInsets.only(right: 16.0),
            child: Center(child: StatusBadge(status: item.status)),
          ),
        ],
      ),
      body: ListView(
        padding: AppSpacing.pagePadding,
        children: [
          // Section 31 Stock Header Card
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(item.productName, style: AppTextStyles.headlineLarge),
                    StatusBadge(status: item.status),
                  ],
                ),
                const SizedBox(height: 2),
                Text(item.sku, style: AppTextStyles.monoCode),
                const Divider(height: 24),
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('WAREHOUSE', style: AppTextStyles.labelSmall),
                          const SizedBox(height: 2),
                          Text(item.warehouseName, style: AppTextStyles.labelLarge),
                        ],
                      ),
                    ),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('LOCATION', style: AppTextStyles.labelSmall),
                          const SizedBox(height: 2),
                          Text(item.locationName, style: AppTextStyles.labelLarge),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                // Section 31 Arithmetic formula
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.canvas,
                    borderRadius: AppSpacing.borderRadiusMd,
                    border: Border.all(color: AppColors.line),
                  ),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          _buildMetricTile('ON HAND', '${item.onHand.toInt()} $uom', AppColors.ink),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 4.0),
                            child: Text('-', style: AppTextStyles.headlineMedium.copyWith(color: AppColors.inkTertiary)),
                          ),
                          _buildMetricTile('RESERVED', '${item.reserved.toInt()} $uom', AppColors.statusWaiting),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 4.0),
                            child: Text('=', style: AppTextStyles.headlineMedium.copyWith(color: AppColors.inkTertiary)),
                          ),
                          _buildMetricTile('FREE TO USE', '${item.freeToUse.toInt()} $uom', AppColors.brand),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'ON HAND  -  RESERVED  =  FREE TO USE',
                        style: AppTextStyles.labelSmall.copyWith(
                          color: AppColors.inkTertiary,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1.0,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.md),

          // Reorder & Cost Summary
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('STOCK THRESHOLDS & VALUATION', style: AppTextStyles.labelSmall),
                const Divider(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Reorder Point', style: AppTextStyles.bodySmall),
                    Text('${item.reorderPoint.toInt()} $uom', style: AppTextStyles.labelLarge),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Cost Per Unit', style: AppTextStyles.bodySmall),
                    Text('₹${item.costPerUnit.toStringAsFixed(2)}', style: AppTextStyles.labelLarge),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Total Asset Value', style: AppTextStyles.bodySmall),
                    Text('₹${(item.costPerUnit * item.onHand).toStringAsFixed(2)}', style: AppTextStyles.labelLarge.copyWith(color: AppColors.brand)),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.md),

          // Recent Movements for this Product
          Text('Recent Product Moves', style: AppTextStyles.labelLarge.copyWith(color: AppColors.inkSecondary)),
          const SizedBox(height: AppSpacing.sm),
          historyAsync.when(
            loading: () => const LoadingView(message: 'Loading ledger movements...'),
            error: (e, _) => Text('Could not load history: $e', style: AppTextStyles.bodySmall),
            data: (moves) {
              final prodMoves = moves.where((m) => m.productId == item.productId || m.sku == item.sku).toList();
              if (prodMoves.isEmpty) {
                return const AppCard(
                  child: Center(
                    child: Padding(
                      padding: EdgeInsets.symmetric(vertical: 12.0),
                      child: Text('No historical ledger transactions recorded for this item.', style: TextStyle(color: AppColors.inkTertiary)),
                    ),
                  ),
                );
              }
              return Column(
                children: prodMoves.take(5).map((m) {
                  final isIncoming = m.moveType.toLowerCase() == 'receipt';
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8.0),
                    child: AppCard(
                      child: Row(
                        children: [
                          Icon(
                            isIncoming ? Icons.arrow_downward_rounded : Icons.arrow_upward_rounded,
                            color: isIncoming ? AppColors.statusDone : AppColors.statusCancelled,
                            size: 20,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(m.reference, style: AppTextStyles.labelLarge),
                                Text(
                                  '${m.fromLocationName} → ${m.toLocationName}',
                                  style: AppTextStyles.bodySmall,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(
                                '${isIncoming ? '+' : '-'}${m.quantity.toInt()} $uom',
                                style: AppTextStyles.labelLarge.copyWith(
                                  color: isIncoming ? AppColors.statusDone : AppColors.statusCancelled,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              StatusBadge(status: m.status, fontSize: 10),
                            ],
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
