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
import 'create_adjustment_screen.dart';
import 'adjustment_detail_screen.dart';

class AdjustmentListScreen extends ConsumerStatefulWidget {
  const AdjustmentListScreen({super.key});

  @override
  ConsumerState<AdjustmentListScreen> createState() => _AdjustmentListScreenState();
}

class _AdjustmentListScreenState extends ConsumerState<AdjustmentListScreen> {
  final _searchController = TextEditingController();
  String _statusFilter = 'ALL';
  String _searchQuery = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Widget _buildFilterChip(String label, String value) {
    final isSelected = _statusFilter == value;
    return GestureDetector(
      onTap: () => setState(() => _statusFilter = value),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.brand : AppColors.panel,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: isSelected ? AppColors.brand : AppColors.line),
        ),
        child: Text(
          label,
          style: AppTextStyles.labelSmall.copyWith(
            color: isSelected ? Colors.white : AppColors.ink,
            fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final adjustmentsAsync = ref.watch(adjustmentsFutureProvider);

    return Scaffold(
      backgroundColor: AppColors.canvas,
      appBar: AppBar(
        leading: BackButton(
          onPressed: () {
            if (context.canPop()) {
              context.pop();
            } else {
              context.go('/home');
            }
          },
        ),
        title: Text('Stock Adjustments', style: AppTextStyles.headlineLarge),
      ),

      body: Column(
        children: [
          // Search & Filters
          Container(
            padding: const EdgeInsets.all(AppSpacing.md),
            color: AppColors.panel,
            child: Column(
              children: [
                TextField(
                  controller: _searchController,
                  onChanged: (val) => setState(() => _searchQuery = val.trim().toLowerCase()),
                  decoration: InputDecoration(
                    hintText: 'Search reference, product, reason...',
                    prefixIcon: const Icon(Icons.search_rounded, color: AppColors.inkTertiary),
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
                    contentPadding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _buildFilterChip('All', 'ALL'),
                      const SizedBox(width: 8),
                      _buildFilterChip('Draft', 'DRAFT'),
                      const SizedBox(width: 8),
                      _buildFilterChip('Done', 'DONE'),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Adjustments List
          Expanded(
            child: RefreshIndicator(
              onRefresh: () async => ref.invalidate(adjustmentsFutureProvider),
              child: adjustmentsAsync.when(
                loading: () => const LoadingView(message: 'Loading adjustments...'),
                error: (err, _) => ErrorView(
                  message: err.toString(),
                  onRetry: () => ref.invalidate(adjustmentsFutureProvider),
                ),
                data: (adjustments) {
                  final filtered = adjustments.where((a) {
                    if (_statusFilter != 'ALL' && a.status.toUpperCase() != _statusFilter) {
                      return false;
                    }
                    if (_searchQuery.isNotEmpty) {
                      final q = _searchQuery;
                      final matchRef = a.reference.toLowerCase().contains(q);
                      final matchProd = a.productName.toLowerCase().contains(q);
                      final matchSku = a.sku.toLowerCase().contains(q);
                      final matchReason = (a.reason ?? '').toLowerCase().contains(q);
                      if (!matchRef && !matchProd && !matchSku && !matchReason) {
                        return false;
                      }
                    }
                    return true;
                  }).toList();

                  if (filtered.isEmpty) {
                    return const EmptyView(
                      title: 'No Adjustments Found',
                      subtitle: 'Reconcile physical inventory counts against system records.',
                    );
                  }

                  return ListView.separated(
                    padding: AppSpacing.pagePadding,
                    itemCount: filtered.length,
                    separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.sm),
                    itemBuilder: (context, index) {
                      final item = filtered[index];
                      final diff = item.difference ?? 0.0;
                      final diffColor = diff > 0
                          ? AppColors.statusDone
                          : (diff < 0 ? AppColors.statusCancelled : AppColors.ink);
                      final diffPrefix = diff > 0 ? '+' : '';

                      return AppCard(
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => AdjustmentDetailScreen(initialAdjustment: item),
                            ),
                          );
                        },
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(item.reference, style: AppTextStyles.monoCode.copyWith(fontWeight: FontWeight.w700)),
                                StatusBadge(status: item.status),
                              ],
                            ),
                            const SizedBox(height: AppSpacing.sm),
                            Text(item.productName, style: AppTextStyles.headlineMedium),
                            const SizedBox(height: 2),
                            Text('SKU: ${item.sku}', style: AppTextStyles.bodySmall),
                            
                            if (item.reason != null && item.reason!.isNotEmpty) ...[
                              const SizedBox(height: AppSpacing.sm),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: AppColors.canvas,
                                  borderRadius: BorderRadius.circular(4),
                                  border: Border.all(color: AppColors.line),
                                ),
                                child: Text(
                                  'Reason: ${item.reason}',
                                  style: AppTextStyles.labelSmall.copyWith(color: AppColors.inkSecondary),
                                ),
                              ),
                            ],

                            const Divider(height: 16),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text('Location', style: AppTextStyles.labelSmall),
                                    const SizedBox(height: 2),
                                    Text(
                                      item.fromLocationName.isNotEmpty ? item.fromLocationName : 'Warehouse Location',
                                      style: AppTextStyles.bodySmall.copyWith(color: AppColors.ink),
                                    ),
                                  ],
                                ),
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    Text('Adjustment', style: AppTextStyles.labelSmall),
                                    const SizedBox(height: 2),
                                    Text(
                                      '$diffPrefix${diff.toInt()} units',
                                      style: AppTextStyles.headlineMedium.copyWith(color: diffColor),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ],
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: AppColors.brand,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add_rounded),
        label: const Text('New Count'),
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const CreateAdjustmentScreen()),
          );
        },
      ),
    );
  }
}
