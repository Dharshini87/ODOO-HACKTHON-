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
import 'create_receipt_screen.dart';
import 'receipt_detail_screen.dart';

class ReceiptListScreen extends ConsumerStatefulWidget {
  const ReceiptListScreen({super.key});

  @override
  ConsumerState<ReceiptListScreen> createState() => _ReceiptListScreenState();
}

class _ReceiptListScreenState extends ConsumerState<ReceiptListScreen> {
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
    final receiptsAsync = ref.watch(receiptsFutureProvider);

    return Scaffold(
      backgroundColor: AppColors.canvas,
      appBar: AppBar(
        title: Text('Inbound Receipts', style: AppTextStyles.headlineLarge),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            onPressed: () => ref.invalidate(receiptsFutureProvider),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: AppColors.brand,
        icon: const Icon(Icons.add_rounded, color: Colors.white),
        label: const Text('New Receipt', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => const CreateReceiptScreen()),
          );
        },
      ),
      body: Column(
        children: [
          // Search & Filter Header
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: TextField(
              controller: _searchController,
              onChanged: (v) => setState(() => _searchQuery = v.trim().toLowerCase()),
              decoration: InputDecoration(
                hintText: 'Search reference or vendor...',
                prefixIcon: const Icon(Icons.search_rounded, size: 20),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear_rounded, size: 18),
                        onPressed: () {
                          _searchController.clear();
                          setState(() => _searchQuery = '');
                        },
                      )
                    : null,
              ),
            ),
          ),

          // Status Filter Chips
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
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
          const SizedBox(height: 8),

          // Receipts List
          Expanded(
            child: RefreshIndicator(
              onRefresh: () async => ref.invalidate(receiptsFutureProvider),
              child: receiptsAsync.when(
                loading: () => const LoadingView(message: 'Loading receipts...'),
                error: (e, _) => ErrorView(
                  message: e.toString(),
                  onRetry: () => ref.invalidate(receiptsFutureProvider),
                ),
                data: (items) {
                  final filtered = items.where((it) {
                    final statusMatch = _statusFilter == 'ALL' || it.status.toUpperCase() == _statusFilter;
                    final queryMatch = _searchQuery.isEmpty ||
                        it.reference.toLowerCase().contains(_searchQuery) ||
                        it.productName.toLowerCase().contains(_searchQuery) ||
                        (it.contact ?? '').toLowerCase().contains(_searchQuery);
                    return statusMatch && queryMatch;
                  }).toList();

                  if (filtered.isEmpty) {
                    return const EmptyView(
                      title: 'No Receipts Found',
                      subtitle: 'Create a new incoming receipt or clear filters',
                    );
                  }

                  return ListView.separated(
                    padding: AppSpacing.pagePadding,
                    itemCount: filtered.length,
                    separatorBuilder: (context, index) => const SizedBox(height: AppSpacing.sm),
                    itemBuilder: (context, index) {
                      final item = filtered[index];
                      return AppCard(
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => ReceiptDetailScreen(initialReceipt: item),
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
                            Text('Supplier: ${item.contact ?? "Vendor"}', style: AppTextStyles.bodySmall),
                            const Divider(height: 16),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text('Destination: ${item.toLocationName}', style: AppTextStyles.labelSmall),
                                Text(
                                  '+${item.quantity.toInt()} units',
                                  style: AppTextStyles.headlineMedium.copyWith(color: AppColors.brand, fontWeight: FontWeight.bold),
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
    );
  }
}
