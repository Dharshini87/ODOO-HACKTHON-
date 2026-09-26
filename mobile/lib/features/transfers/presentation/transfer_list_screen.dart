import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_spacing.dart';
import '../../../app/theme/app_text_styles.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/status_badge.dart';
import '../../../core/widgets/loading_view.dart';
import '../../../core/widgets/error_view.dart';
import '../../../core/widgets/empty_view.dart';
import '../../../shared/providers/inventory_providers.dart';
import 'create_transfer_screen.dart';
import 'transfer_detail_screen.dart';

class TransferListScreen extends ConsumerStatefulWidget {
  const TransferListScreen({super.key});

  @override
  ConsumerState<TransferListScreen> createState() => _TransferListScreenState();
}

class _TransferListScreenState extends ConsumerState<TransferListScreen> {
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
    final transfersAsync = ref.watch(transfersFutureProvider);

    return Scaffold(
      backgroundColor: AppColors.canvas,
      appBar: AppBar(
        title: Text('Internal Transfers', style: AppTextStyles.headlineLarge),
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
                    hintText: 'Search reference, product, route...',
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
                      _buildFilterChip('Ready', 'READY'),
                      const SizedBox(width: 8),
                      _buildFilterChip('Done', 'DONE'),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Transfers List
          Expanded(
            child: RefreshIndicator(
              onRefresh: () async => ref.invalidate(transfersFutureProvider),
              child: transfersAsync.when(
                loading: () => const LoadingView(message: 'Loading transfers...'),
                error: (err, _) => ErrorView(
                  message: err.toString(),
                  onRetry: () => ref.invalidate(transfersFutureProvider),
                ),
                data: (transfers) {
                  final filtered = transfers.where((t) {
                    if (_statusFilter != 'ALL' && t.status.toUpperCase() != _statusFilter) {
                      return false;
                    }
                    if (_searchQuery.isNotEmpty) {
                      final q = _searchQuery;
                      final matchRef = t.reference.toLowerCase().contains(q);
                      final matchProd = t.productName.toLowerCase().contains(q);
                      final matchSku = t.sku.toLowerCase().contains(q);
                      final matchRoute = '${t.fromLocationName} ${t.toLocationName}'.toLowerCase().contains(q);
                      if (!matchRef && !matchProd && !matchSku && !matchRoute) {
                        return false;
                      }
                    }
                    return true;
                  }).toList();

                  if (filtered.isEmpty) {
                    return const EmptyView(
                      title: 'No Transfers Found',
                      subtitle: 'Move inventory between warehouse locations to see entries here.',
                    );
                  }

                  return ListView.separated(
                    padding: AppSpacing.pagePadding,
                    itemCount: filtered.length,
                    separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.sm),
                    itemBuilder: (context, index) {
                      final item = filtered[index];

                      return AppCard(
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => TransferDetailScreen(initialTransfer: item),
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
                            const Divider(height: 16),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text('Route', style: AppTextStyles.labelSmall),
                                      const SizedBox(height: 2),
                                      Row(
                                        children: [
                                          Flexible(
                                            child: Text(
                                              item.fromLocationName,
                                              style: AppTextStyles.bodySmall.copyWith(color: AppColors.ink),
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                          const Padding(
                                            padding: EdgeInsets.symmetric(horizontal: 4),
                                            child: Icon(Icons.arrow_forward_rounded, size: 14, color: AppColors.brand),
                                          ),
                                          Flexible(
                                            child: Text(
                                              item.toLocationName,
                                              style: AppTextStyles.bodySmall.copyWith(color: AppColors.ink),
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    Text('Transfer Qty', style: AppTextStyles.labelSmall),
                                    const SizedBox(height: 2),
                                    Text(
                                      '${item.quantity.toInt()} units',
                                      style: AppTextStyles.headlineMedium.copyWith(color: AppColors.brand),
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
        label: const Text('New Transfer'),
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const CreateTransferScreen()),
          );
        },
      ),
    );
  }
}
