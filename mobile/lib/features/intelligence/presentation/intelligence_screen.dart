import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_spacing.dart';
import '../../../app/theme/app_text_styles.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/loading_view.dart';
import '../../../core/widgets/error_view.dart';
import '../../../core/widgets/empty_view.dart';
import '../../../core/widgets/access_denied_view.dart';
import '../../../shared/providers/inventory_providers.dart';
import '../../auth/presentation/auth_provider.dart';

class IntelligenceScreen extends ConsumerStatefulWidget {
  const IntelligenceScreen({super.key});

  @override
  ConsumerState<IntelligenceScreen> createState() => _IntelligenceScreenState();
}

class _IntelligenceScreenState extends ConsumerState<IntelligenceScreen> with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  final _searchController = TextEditingController();
  String _searchQuery = '';

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

  Widget _buildStockoutCard(StockoutPredictionItem item) {
    final hasHistory = item.hasSufficientHistory;
    final isCritical = (item.estimatedDaysToStockout ?? 999) <= 3;
    final isWarning = (item.estimatedDaysToStockout ?? 999) <= 7;

    final badgeColor = !hasHistory
        ? AppColors.inkTertiary
        : (isCritical
            ? AppColors.statusCancelled
            : (isWarning ? AppColors.statusWaiting : AppColors.statusDone));

    return AppCard(
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
                  color: badgeColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: badgeColor),
                ),
                child: Text(
                  hasHistory
                      ? (isCritical
                          ? 'CRITICAL DEPLETION'
                          : (isWarning ? 'REORDER SOON' : 'STABLE'))
                      : 'NO HISTORY',
                  style: AppTextStyles.labelSmall.copyWith(color: badgeColor, fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text('SKU: ${item.sku}', style: AppTextStyles.bodySmall),
          const Divider(height: 16),

          if (!hasHistory) ...[
            Container(
              padding: const EdgeInsets.all(AppSpacing.md),
              decoration: BoxDecoration(
                color: AppColors.canvas,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppColors.line),
              ),
              child: Row(
                children: [
                  const Icon(Icons.info_outline_rounded, color: AppColors.inkSecondary, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      item.message ?? 'Not enough historical movement data.',
                      style: AppTextStyles.bodySmall.copyWith(
                        color: AppColors.inkSecondary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _buildStat('Current Stock', '${item.currentStock.toInt()} units'),
                _buildStat('Reorder Level', '${item.reorderLevel.toInt()} units'),
              ],
            ),
          ] else ...[
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _buildStat('Current Stock', '${item.currentStock.toInt()} units'),
                _buildStat('Daily Usage', '${item.averageDailyUsage ?? 0}/day'),
                _buildStat('Reorder Level', '${item.reorderLevel.toInt()} units'),
              ],
            ),
            const Divider(height: 16),
            Container(
              padding: const EdgeInsets.all(AppSpacing.sm),
              decoration: BoxDecoration(
                color: AppColors.panel,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  Column(
                    children: [
                      Text('Days to Reorder', style: AppTextStyles.labelSmall),
                      const SizedBox(height: 2),
                      Text(
                        item.estimatedDaysToReorder != null
                            ? '${item.estimatedDaysToReorder} days'
                            : 'Immediate',
                        style: AppTextStyles.headlineSmall.copyWith(
                          color: (item.estimatedDaysToReorder ?? 0) <= 0
                              ? AppColors.statusCancelled
                              : AppColors.ink,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                  Container(height: 24, width: 1, color: AppColors.line),
                  Column(
                    children: [
                      Text('Days to Stockout', style: AppTextStyles.labelSmall),
                      const SizedBox(height: 2),
                      Text(
                        item.estimatedDaysToStockout != null
                            ? '${item.estimatedDaysToStockout} days'
                            : '0 days',
                        style: AppTextStyles.headlineSmall.copyWith(
                          color: (item.estimatedDaysToStockout ?? 0) <= 3
                              ? AppColors.statusCancelled
                              : AppColors.brand,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildReorderCard(ReorderRecommendationItem item) {
    final hasHistory = item.hasSufficientHistory;

    return AppCard(
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
              if (item.recommendedReorderQuantity > 0)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.brand.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: AppColors.brand),
                  ),
                  child: Text(
                    'REORDER RECOMMENDED',
                    style: AppTextStyles.labelSmall.copyWith(color: AppColors.brand, fontWeight: FontWeight.w700),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 2),
          Text('SKU: ${item.sku}', style: AppTextStyles.bodySmall),
          const Divider(height: 16),

          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _buildStat('Current Stock', '${item.currentStock.toInt()} units'),
              _buildStat('Average Usage', hasHistory ? '${item.averageUsage ?? 0}/day' : 'N/A'),
              _buildStat('Target Coverage', '${item.targetCoverage} days'),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),

          // Recommended Quantity Highlight
          Container(
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(
              color: item.recommendedReorderQuantity > 0
                  ? AppColors.brand.withValues(alpha: 0.08)
                  : AppColors.canvas,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: item.recommendedReorderQuantity > 0 ? AppColors.brand : AppColors.line,
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Recommended Reorder', style: AppTextStyles.labelSmall),
                    const SizedBox(height: 2),
                    Text(
                      '${item.recommendedReorderQuantity.toInt()} units',
                      style: AppTextStyles.headlineLarge.copyWith(
                        color: item.recommendedReorderQuantity > 0 ? AppColors.brand : AppColors.ink,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
                Icon(
                  item.recommendedReorderQuantity > 0 ? Icons.add_shopping_cart_rounded : Icons.check_circle_outline_rounded,
                  color: item.recommendedReorderQuantity > 0 ? AppColors.brand : AppColors.statusDone,
                  size: 28,
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.sm),

          // Transparent Calculation / Explanation Card (Section 28)
          Container(
            padding: const EdgeInsets.all(AppSpacing.sm),
            decoration: BoxDecoration(
              color: AppColors.panel,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.calculate_outlined, size: 16, color: AppColors.inkSecondary),
                    const SizedBox(width: 6),
                    Text(
                      'Transparent Arithmetic Explanation',
                      style: AppTextStyles.labelSmall.copyWith(fontWeight: FontWeight.w700),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  item.explanation,
                  style: AppTextStyles.bodySmall.copyWith(
                    color: AppColors.inkSecondary,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStat(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: AppTextStyles.labelSmall),
        const SizedBox(height: 2),
        Text(
          value,
          style: AppTextStyles.bodySmall.copyWith(color: AppColors.ink, fontWeight: FontWeight.w600),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authProvider).user;
    if (user != null && !user.isManager) {
      return const AccessRestrictedScaffold(
        title: 'Inventory Intelligence',
        message: 'Only Inventory Managers have permission to access inventory intelligence, turnover projections, and stock analytics.',
      );
    }

    final stockoutAsync = ref.watch(stockoutFutureProvider);
    final reorderAsync = ref.watch(reorderFutureProvider);
    final currentCoverage = ref.watch(reorderTargetCoverageProvider);

    return Scaffold(
      backgroundColor: AppColors.canvas,
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Inventory Intelligence', style: AppTextStyles.headlineLarge),
            Text(
              'Transparent calculations • Zero LLM chatbots',
              style: AppTextStyles.bodySmall.copyWith(color: AppColors.inkSecondary),
            ),
          ],
        ),
        bottom: TabBar(
          controller: _tabController,
          labelColor: AppColors.brand,
          unselectedLabelColor: AppColors.inkTertiary,
          indicatorColor: AppColors.brand,
          indicatorWeight: 3,
          labelStyle: AppTextStyles.labelLarge,
          tabs: const [
            Tab(text: 'Stockout Velocity'),
            Tab(text: 'Reorder Recommendations'),
          ],
        ),
      ),
      body: Column(
        children: [
          // Search & Filter header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
            color: AppColors.panel,
            child: TextField(
              controller: _searchController,
              onChanged: (val) => setState(() => _searchQuery = val.trim().toLowerCase()),
              decoration: InputDecoration(
                hintText: 'Filter by product name or SKU...',
                prefixIcon: const Icon(Icons.search_rounded, size: 20, color: AppColors.inkTertiary),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear_rounded, size: 18),
                        onPressed: () {
                          _searchController.clear();
                          setState(() => _searchQuery = '');
                        },
                      )
                    : null,
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
              ),
            ),
          ),

          // Tabs
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                // Tab 1: Stockout Velocity
                RefreshIndicator(
                  onRefresh: () async => ref.invalidate(stockoutFutureProvider),
                  child: stockoutAsync.when(
                    loading: () => const LoadingView(message: 'Calculating stockout velocity...'),
                    error: (err, _) => ErrorView(message: err.toString(), onRetry: () => ref.invalidate(stockoutFutureProvider)),
                    data: (list) {
                      final filtered = list.where((it) {
                        if (_searchQuery.isEmpty) return true;
                        return it.productName.toLowerCase().contains(_searchQuery) ||
                            it.sku.toLowerCase().contains(_searchQuery);
                      }).toList();

                      if (filtered.isEmpty) {
                        return const EmptyView(
                          title: 'No Products Tracked',
                          subtitle: 'Product stockout projections will appear once inventory is registered.',
                        );
                      }

                      return ListView.separated(
                        padding: AppSpacing.pagePadding,
                        itemCount: filtered.length,
                        separatorBuilder: (context, index) => const SizedBox(height: AppSpacing.sm),
                        itemBuilder: (context, index) => _buildStockoutCard(filtered[index]),
                      );
                    },
                  ),
                ),

                // Tab 2: Reorder Recommendations
                RefreshIndicator(
                  onRefresh: () async => ref.invalidate(reorderFutureProvider),
                  child: Column(
                    children: [
                      // Target Coverage Selector
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: 8),
                        color: AppColors.canvas,
                        child: Row(
                          children: [
                            Text('Target Coverage: ', style: AppTextStyles.labelSmall.copyWith(fontWeight: FontWeight.w600)),
                            const SizedBox(width: 8),
                            _buildCoverageChip(15, currentCoverage),
                            const SizedBox(width: 6),
                            _buildCoverageChip(30, currentCoverage),
                            const SizedBox(width: 6),
                            _buildCoverageChip(60, currentCoverage),
                          ],
                        ),
                      ),
                      const Divider(height: 1),

                      Expanded(
                        child: reorderAsync.when(
                          loading: () => const LoadingView(message: 'Computing reorder recommendations...'),
                          error: (err, _) => ErrorView(message: err.toString(), onRetry: () => ref.invalidate(reorderFutureProvider)),
                          data: (list) {
                            final filtered = list.where((it) {
                              if (_searchQuery.isEmpty) return true;
                              return it.productName.toLowerCase().contains(_searchQuery) ||
                                  it.sku.toLowerCase().contains(_searchQuery);
                            }).toList();

                            if (filtered.isEmpty) {
                              return const EmptyView(
                                title: 'No Products Tracked',
                                subtitle: 'Reorder recommendations will appear once products are created.',
                              );
                            }

                            return ListView.separated(
                              padding: AppSpacing.pagePadding,
                              itemCount: filtered.length,
                              separatorBuilder: (context, index) => const SizedBox(height: AppSpacing.sm),
                              itemBuilder: (context, index) => _buildReorderCard(filtered[index]),
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCoverageChip(int days, int selectedDays) {
    final isSelected = days == selectedDays;
    return GestureDetector(
      onTap: () {
        ref.read(reorderTargetCoverageProvider.notifier).setCoverage(days);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.brand : AppColors.panel,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: isSelected ? AppColors.brand : AppColors.line),
        ),
        child: Text(
          '$days Days',
          style: AppTextStyles.labelSmall.copyWith(
            color: isSelected ? Colors.white : AppColors.ink,
            fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
      ),
    );
  }
}
