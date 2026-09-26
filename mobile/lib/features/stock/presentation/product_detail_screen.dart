import 'package:flutter/material.dart';
import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_spacing.dart';
import '../../../app/theme/app_text_styles.dart';
import '../../../core/widgets/app_card.dart';

class ProductDetailScreen extends StatelessWidget {
  final Map<String, dynamic> product;

  const ProductDetailScreen({super.key, required this.product});

  @override
  Widget build(BuildContext context) {
    final name = product['name'] as String? ?? 'Product';
    final sku = product['sku'] as String? ?? '';
    final uom = product['unit_of_measure'] as String? ?? 'unit';
    final cost = ((product['unit_cost'] ?? product['cost_per_unit']) as num?)?.toDouble() ?? 0.0;
    final reorder = ((product['reorder_level'] ?? product['reorder_point']) as num?)?.toDouble() ?? 0.0;
    final isActive = (product['is_active'] as bool?) ?? true;

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
                  children: [
                    Container(
                      width: 56,
                      height: 56,
                      decoration: BoxDecoration(
                        color: AppColors.brand.withValues(alpha: 0.12),
                        borderRadius: AppSpacing.borderRadiusMd,
                      ),
                      child: const Icon(Icons.inventory_2_outlined, color: AppColors.brand, size: 30),
                    ),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(name, style: AppTextStyles.headlineMedium),
                          const SizedBox(height: 2),
                          Text('SKU: $sku', style: AppTextStyles.monoCode),
                        ],
                      ),
                    ),
                  ],
                ),
                const Divider(height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Unit of Measure', style: AppTextStyles.bodySmall),
                    Text(uom.toUpperCase(), style: AppTextStyles.labelLarge),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Cost per Unit', style: AppTextStyles.bodySmall),
                    Text('₹${cost.toStringAsFixed(2)}', style: AppTextStyles.labelLarge),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Reorder Point Threshold', style: AppTextStyles.bodySmall),
                    Text('${reorder.toInt()} $uom', style: AppTextStyles.labelLarge.copyWith(color: AppColors.amber)),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Catalog Status', style: AppTextStyles.bodySmall),
                    Text(isActive ? 'ACTIVE' : 'INACTIVE',
                        style: AppTextStyles.labelSmall.copyWith(
                          color: isActive ? AppColors.statusDone : AppColors.statusCancelled,
                          fontWeight: FontWeight.bold,
                        )),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
