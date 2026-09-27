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
import '../../../core/widgets/empty_view.dart';
import '../../../shared/providers/inventory_providers.dart';
import '../../auth/presentation/auth_provider.dart';
import 'stock_detail_screen.dart';
import 'product_detail_screen.dart';

class StockScreen extends ConsumerStatefulWidget {
  const StockScreen({super.key});

  @override
  ConsumerState<StockScreen> createState() => _StockScreenState();
}

class _StockScreenState extends ConsumerState<StockScreen> with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  final _searchController = TextEditingController();
  String _filter = '';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Widget _buildArithmeticTile(String title, String value, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 4.0),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: AppSpacing.borderRadiusSm,
          border: Border.all(color: color.withValues(alpha: 0.2)),
        ),
        child: Column(
          children: [
            Text(
              title,
              style: AppTextStyles.labelSmall.copyWith(
                color: color,
                fontSize: 9,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.3,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 2),
            Text(
              value,
              style: AppTextStyles.headlineSmall.copyWith(
                color: color,
                fontWeight: FontWeight.w700,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  /// Section 31: STOCK MOBILE UI
  /// Product Name, SKU, Main Warehouse, Rack A, On Hand: X kg, Reserved: X kg, Free to Use: X kg, NORMAL
  /// Relationship: ON HAND - RESERVED = FREE TO USE
  Widget _buildStockCard(StockItem item) {
    final uom = item.unitOfMeasure;

    return AppCard(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => StockDetailScreen(item: item)),
        );
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.productName,
                      style: AppTextStyles.headlineMedium,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      item.sku,
                      style: AppTextStyles.monoCode.copyWith(color: AppColors.inkSecondary),
                    ),
                  ],
                ),
              ),
              StatusBadge(status: item.status),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              const Icon(Icons.warehouse_outlined, size: 14, color: AppColors.inkTertiary),
              const SizedBox(width: 4),
              Text(
                item.warehouseName,
                style: AppTextStyles.bodySmall.copyWith(fontWeight: FontWeight.w600, color: AppColors.ink),
              ),
              const SizedBox(width: 8),
              const Text('•', style: TextStyle(color: AppColors.inkTertiary)),
              const SizedBox(width: 8),
              const Icon(Icons.grid_view_rounded, size: 14, color: AppColors.inkTertiary),
              const SizedBox(width: 4),
              Text(
                item.locationName,
                style: AppTextStyles.bodySmall.copyWith(fontWeight: FontWeight.w600, color: AppColors.ink),
              ),
            ],
          ),
          const Divider(height: 16),
          // Section 31 Visual Arithmetic Relationship
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            decoration: BoxDecoration(
              color: AppColors.canvas,
              borderRadius: AppSpacing.borderRadiusSm,
              border: Border.all(color: AppColors.line),
            ),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    _buildArithmeticTile(
                      'ON HAND',
                      '${item.onHand.toInt()} $uom',
                      AppColors.ink,
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4.0),
                      child: Text(
                        '-',
                        style: AppTextStyles.headlineSmall.copyWith(
                          color: AppColors.inkTertiary,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    _buildArithmeticTile(
                      'RESERVED',
                      '${item.reserved.toInt()} $uom',
                      AppColors.statusWaiting,
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4.0),
                      child: Text(
                        '=',
                        style: AppTextStyles.headlineSmall.copyWith(
                          color: AppColors.inkTertiary,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    _buildArithmeticTile(
                      'FREE TO USE',
                      '${item.freeToUse.toInt()} $uom',
                      AppColors.brand,
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  'ON HAND  -  RESERVED  =  FREE TO USE',
                  style: AppTextStyles.labelSmall.copyWith(
                    color: AppColors.inkTertiary,
                    fontSize: 9,
                    letterSpacing: 0.6,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProductCard(Map<String, dynamic> prod) {
    final name = prod['name'] as String? ?? 'Product';
    final sku = prod['sku'] as String? ?? '';
    final uom = prod['unit_of_measure'] as String? ?? 'unit';
    final cost = ((prod['unit_cost'] ?? prod['cost_per_unit']) as num?)?.toDouble() ?? 0.0;
    final reorder = ((prod['reorder_level'] ?? prod['reorder_point']) as num?)?.toDouble() ?? 0.0;

    return AppCard(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => ProductDetailScreen(product: prod)),
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
            child: const Icon(Icons.inventory_2_outlined, color: AppColors.brand, size: 24),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name, style: AppTextStyles.headlineMedium),
                const SizedBox(height: 2),
                Text('SKU: $sku • Unit: $uom', style: AppTextStyles.bodySmall),
                Text('Cost: ₹${cost.toStringAsFixed(2)} • Reorder: ${reorder.toInt()}', style: AppTextStyles.labelSmall),
              ],
            ),
          ),
          const Icon(Icons.chevron_right_rounded, color: AppColors.inkTertiary, size: 20),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authProvider).user;
    final stockAsync = ref.watch(stockFutureProvider);
    final productsAsync = ref.watch(productsFutureProvider);

    return Scaffold(
      backgroundColor: AppColors.canvas,
      appBar: AppBar(
        title: Text('Stock & Catalog', style: AppTextStyles.headlineLarge),
        bottom: TabBar(
          controller: _tabController,
          labelColor: AppColors.brand,
          unselectedLabelColor: AppColors.inkTertiary,
          indicatorColor: AppColors.brand,
          indicatorWeight: 3,
          labelStyle: AppTextStyles.labelLarge,
          tabs: const [
            Tab(text: 'On-Hand Stock'),
            Tab(text: 'Product Catalog'),
          ],
        ),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: TextField(
              controller: _searchController,
              onChanged: (v) => setState(() => _filter = v.trim().toLowerCase()),
              decoration: InputDecoration(
                hintText: 'Search by product name or SKU...',
                prefixIcon: const Icon(Icons.search_rounded, size: 20),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                suffixIcon: _filter.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear_rounded, size: 18),
                        onPressed: () {
                          _searchController.clear();
                          setState(() => _filter = '');
                        },
                      )
                    : null,
              ),
            ),
          ),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                // Stock Tab
                RefreshIndicator(
                  onRefresh: () async => ref.invalidate(stockFutureProvider),
                  child: stockAsync.when(
                    loading: () => const LoadingView(message: 'Calculating ledger stock...'),
                    error: (err, _) => ErrorView(
                      message: err.toString(),
                      onRetry: () => ref.invalidate(stockFutureProvider),
                    ),
                    data: (items) {
                      final filtered = items.where((it) {
                        return it.productName.toLowerCase().contains(_filter) ||
                            it.sku.toLowerCase().contains(_filter);
                      }).toList();

                      if (filtered.isEmpty) {
                        return const EmptyView(
                          title: 'No Stock Records',
                          subtitle: 'Stock items will appear once moves are recorded',
                        );
                      }
                      return ListView.separated(
                        padding: AppSpacing.pagePadding,
                        itemCount: filtered.length,
                        separatorBuilder: (context, index) => const SizedBox(height: AppSpacing.sm),
                        itemBuilder: (context, i) => _buildStockCard(filtered[i]),
                      );
                    },
                  ),
                ),
                // Products Tab
                RefreshIndicator(
                  onRefresh: () async => ref.invalidate(productsFutureProvider),
                  child: productsAsync.when(
                    loading: () => const LoadingView(message: 'Loading products...'),
                    error: (err, _) => ErrorView(
                      message: err.toString(),
                      onRetry: () => ref.invalidate(productsFutureProvider),
                    ),
                    data: (list) {
                      final filtered = list.where((it) {
                        final name = (it['name'] ?? '').toString().toLowerCase();
                        final sku = (it['sku'] ?? '').toString().toLowerCase();
                        return name.contains(_filter) || sku.contains(_filter);
                      }).toList();

                      if (filtered.isEmpty) {
                        return const EmptyView(
                          title: 'No Products Configured',
                          subtitle: 'Add master products in the Products module',
                        );
                      }
                      return ListView.separated(
                        padding: AppSpacing.pagePadding,
                        itemCount: filtered.length,
                        separatorBuilder: (context, index) => const SizedBox(height: AppSpacing.sm),
                        itemBuilder: (context, i) => _buildProductCard(filtered[i] as Map<String, dynamic>),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      floatingActionButton: (user?.isManager ?? false)
          ? FloatingActionButton.extended(
              backgroundColor: AppColors.brand,
              foregroundColor: Colors.white,
              icon: const Icon(Icons.add_rounded),
              label: const Text('New Product'),
              onPressed: () => context.push('/products/create'),
            )
          : null,
    );
  }
}
