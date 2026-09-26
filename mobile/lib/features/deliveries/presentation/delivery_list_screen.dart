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
import '../../../core/widgets/system_feedback.dart';
import '../../../shared/providers/inventory_providers.dart';
import 'create_delivery_screen.dart';
import 'delivery_detail_screen.dart';

class DeliveryListScreen extends ConsumerStatefulWidget {
  const DeliveryListScreen({super.key});

  @override
  ConsumerState<DeliveryListScreen> createState() => _DeliveryListScreenState();
}

class _DeliveryListScreenState extends ConsumerState<DeliveryListScreen> {
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
    final deliveriesAsync = ref.watch(deliveriesFutureProvider);

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
        title: Text('Outbound Deliveries', style: AppTextStyles.headlineLarge),
        actions: [

          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Check Waiting Deliveries',
            onPressed: () async {
              try {
                final repo = ref.read(deliveriesRepositoryProvider);
                final res = await repo.processWaiting();
                ref.invalidate(deliveriesFutureProvider);
                ref.invalidate(stockFutureProvider);
                final count = res['transitioned_count'] ?? 0;
                if (context.mounted) {
                  AppFeedback.showSuccess(context, 'Processed waiting deliveries. $count transitioned to READY.');
                }
              } catch (e) {
                if (context.mounted) {
                  AppFeedback.showError(context, 'Error processing waiting deliveries: $e');
                }
              }
            },
          ),
        ],
      ),
      body: Column(
        children: [
          // Section 34 Search & Filters
          Container(
            padding: const EdgeInsets.all(AppSpacing.md),
            color: AppColors.panel,
            child: Column(
              children: [
                TextField(
                  controller: _searchController,
                  onChanged: (val) => setState(() => _searchQuery = val.trim().toLowerCase()),
                  decoration: InputDecoration(
                    hintText: 'Search reference or contact...',
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
                      _buildFilterChip('Waiting', 'WAITING'),
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

          // Deliveries List
          Expanded(
            child: RefreshIndicator(
              onRefresh: () async => ref.invalidate(deliveriesFutureProvider),
              child: deliveriesAsync.when(
                loading: () => const LoadingView(message: 'Loading deliveries...'),
                error: (err, _) => ErrorView(
                  message: err.toString(),
                  onRetry: () => ref.invalidate(deliveriesFutureProvider),
                ),
                data: (deliveries) {
                  final filtered = deliveries.where((d) {
                    if (_statusFilter != 'ALL' && d.status.toUpperCase() != _statusFilter) {
                      return false;
                    }
                    if (_searchQuery.isNotEmpty) {
                      final q = _searchQuery;
                      final matchRef = d.reference.toLowerCase().contains(q);
                      final matchProd = d.productName.toLowerCase().contains(q);
                      final matchSku = d.sku.toLowerCase().contains(q);
                      final matchContact = (d.contact ?? '').toLowerCase().contains(q);
                      if (!matchRef && !matchProd && !matchSku && !matchContact) {
                        return false;
                      }
                    }
                    return true;
                  }).toList();

                  if (filtered.isEmpty) {
                    return const EmptyView(
                      title: 'No Deliveries Found',
                      subtitle: 'Create an outbound delivery to start shipping inventory.',
                    );
                  }

                  return ListView.separated(
                    padding: AppSpacing.pagePadding,
                    itemCount: filtered.length,
                    separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.sm),
                    itemBuilder: (context, index) {
                      final item = filtered[index];
                      final isWaiting = item.status.toLowerCase() == 'waiting';
                      final isReady = item.status.toLowerCase() == 'ready';
                      final shortageVal = item.shortage > 0
                          ? item.shortage
                          : (item.quantity - item.freeToUse).clamp(0, 9999).toDouble();

                      return AppCard(
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => DeliveryDetailScreen(initialDelivery: item),
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

                            const SizedBox(height: 8),
                            // Section 32: Requested, Free to Use, and Shortage
                            Row(
                              children: [
                                Text('Requested: ${item.quantity.toInt()} kg', style: AppTextStyles.bodySmall.copyWith(fontWeight: FontWeight.w600)),
                                const SizedBox(width: 12),
                                Text('Free to Use: ${item.freeToUse.toInt()} kg',
                                    style: AppTextStyles.bodySmall.copyWith(
                                      color: isWaiting ? AppColors.statusCancelled : AppColors.brand,
                                      fontWeight: FontWeight.w600,
                                    )),
                                if (isWaiting && shortageVal > 0) ...[
                                  const SizedBox(width: 12),
                                  Text('Shortage: ${shortageVal.toInt()} kg',
                                      style: AppTextStyles.bodySmall.copyWith(
                                        color: AppColors.statusCancelled,
                                        fontWeight: FontWeight.bold,
                                      )),
                                ],
                              ],
                            ),

                            // Section 32 Badges
                            if (isWaiting) ...[
                              const SizedBox(height: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                decoration: BoxDecoration(
                                  color: AppColors.statusCancelledBg,
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(color: AppColors.statusCancelled.withValues(alpha: 0.3)),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(Icons.warning_amber_rounded, size: 14, color: AppColors.statusCancelled),
                                    const SizedBox(width: 6),
                                    Text(
                                      '⚠ Insufficient Available Stock',
                                      style: AppTextStyles.labelSmall.copyWith(
                                        color: AppColors.statusCancelled,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ] else if (isReady) ...[
                              const SizedBox(height: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                decoration: BoxDecoration(
                                  color: AppColors.statusDoneBg,
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(color: AppColors.statusDone.withValues(alpha: 0.3)),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(Icons.check_circle_outline_rounded, size: 14, color: AppColors.statusDone),
                                    const SizedBox(width: 6),
                                    Text(
                                      '✓ Available',
                                      style: AppTextStyles.labelSmall.copyWith(
                                        color: AppColors.statusDone,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],

                            const Divider(height: 16),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Expanded(
                                  child: Text(
                                    '${item.fromLocationName} → ${item.contact ?? item.toLocationName}',
                                    style: AppTextStyles.bodySmall.copyWith(color: AppColors.inkTertiary),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                Text(
                                  '${item.quantity.toInt()} kg',
                                  style: AppTextStyles.headlineSmall.copyWith(color: AppColors.brand, fontWeight: FontWeight.bold),
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
        label: const Text('New Delivery'),
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const CreateDeliveryScreen()),
          );
        },
      ),
    );
  }
}
