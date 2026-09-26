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
import '../../receipts/presentation/receipt_detail_screen.dart';
import '../../receipts/presentation/create_receipt_screen.dart';
import '../../deliveries/presentation/delivery_detail_screen.dart';
import '../../deliveries/presentation/create_delivery_screen.dart';
import '../../transfers/presentation/transfer_detail_screen.dart';
import '../../transfers/presentation/create_transfer_screen.dart';
import '../../adjustments/presentation/adjustment_detail_screen.dart';
import '../../adjustments/presentation/create_adjustment_screen.dart';
import '../../../shared/providers/inventory_providers.dart';

class OperationsScreen extends ConsumerStatefulWidget {
  const OperationsScreen({super.key});

  @override
  ConsumerState<OperationsScreen> createState() => _OperationsScreenState();
}

class _OperationsScreenState extends ConsumerState<OperationsScreen> with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Widget _buildMoveCard(StockMoveItem move) {
    final isAdj = move.moveType.toLowerCase() == 'adjustment';
    final diff = move.difference ?? 0.0;
    final diffPrefix = diff > 0 ? '+' : '';
    final diffColor = diff > 0
        ? AppColors.statusDone
        : (diff < 0 ? AppColors.statusCancelled : AppColors.ink);

    return AppCard(
      onTap: () {
        if (move.moveType.toLowerCase() == 'receipt') {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => ReceiptDetailScreen(initialReceipt: move)),
          );
        } else if (move.moveType.toLowerCase() == 'delivery') {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => DeliveryDetailScreen(initialDelivery: move)),
          );
        } else if (move.moveType.toLowerCase() == 'transfer') {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => TransferDetailScreen(initialTransfer: move)),
          );
        } else if (isAdj) {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => AdjustmentDetailScreen(initialAdjustment: move)),
          );
        }
      },
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
          const SizedBox(height: AppSpacing.sm),
          Text(move.productName, style: AppTextStyles.headlineMedium),
          const SizedBox(height: 2),
          Text('SKU: ${move.sku}', style: AppTextStyles.bodySmall),
          const Divider(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(isAdj ? 'Location & Reason' : 'Route', style: AppTextStyles.labelSmall),
                    const SizedBox(height: 2),
                    Text(
                      isAdj
                          ? '${move.fromLocationName.isNotEmpty ? move.fromLocationName : "Warehouse Floor"}${move.reason != null ? " • ${move.reason}" : ""}'
                          : '${move.fromLocationName} → ${move.toLocationName}',
                      style: AppTextStyles.bodySmall.copyWith(color: AppColors.ink),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(isAdj ? 'Adjustment' : 'Quantity', style: AppTextStyles.labelSmall),
                  const SizedBox(height: 2),
                  Text(
                    isAdj
                        ? '$diffPrefix${diff.toInt()} units'
                        : '${move.quantity.toInt()} units',
                    style: AppTextStyles.headlineMedium.copyWith(color: isAdj ? diffColor : AppColors.brand),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final receiptsAsync = ref.watch(receiptsFutureProvider);
    final deliveriesAsync = ref.watch(deliveriesFutureProvider);
    final transfersAsync = ref.watch(transfersFutureProvider);
    final adjustmentsAsync = ref.watch(adjustmentsFutureProvider);

    return Scaffold(
      backgroundColor: AppColors.canvas,
      appBar: AppBar(
        title: Text('Operations', style: AppTextStyles.headlineLarge),
        bottom: TabBar(
          controller: _tabController,
          labelColor: AppColors.brand,
          unselectedLabelColor: AppColors.inkTertiary,
          indicatorColor: AppColors.brand,
          indicatorWeight: 3,
          isScrollable: true,
          labelStyle: AppTextStyles.labelLarge,
          tabs: const [
            Tab(text: 'Receipts'),
            Tab(text: 'Deliveries'),
            Tab(text: 'Transfers'),
            Tab(text: 'Adjustments'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          // Receipts Tab
          RefreshIndicator(
            onRefresh: () async => ref.invalidate(receiptsFutureProvider),
            child: receiptsAsync.when(
              loading: () => const LoadingView(message: 'Loading receipts...'),
              error: (err, _) => ErrorView(message: err.toString(), onRetry: () => ref.invalidate(receiptsFutureProvider)),
              data: (list) => list.isEmpty
                  ? const EmptyView(title: 'No Receipts Found', subtitle: 'Incoming goods will appear here')
                  : ListView.separated(
                      padding: AppSpacing.pagePadding,
                      itemCount: list.length,
                      separatorBuilder: (context, index) => const SizedBox(height: AppSpacing.sm),
                      itemBuilder: (context, i) => _buildMoveCard(list[i]),
                    ),
            ),
          ),
          // Deliveries Tab
          RefreshIndicator(
            onRefresh: () async => ref.invalidate(deliveriesFutureProvider),
            child: deliveriesAsync.when(
              loading: () => const LoadingView(message: 'Loading deliveries...'),
              error: (err, _) => ErrorView(message: err.toString(), onRetry: () => ref.invalidate(deliveriesFutureProvider)),
              data: (list) => list.isEmpty
                  ? const EmptyView(title: 'No Deliveries Found', subtitle: 'Outbound shipments will appear here')
                  : ListView.separated(
                      padding: AppSpacing.pagePadding,
                      itemCount: list.length,
                      separatorBuilder: (context, index) => const SizedBox(height: AppSpacing.sm),
                      itemBuilder: (context, i) => _buildMoveCard(list[i]),
                    ),
            ),
          ),
          // Transfers Tab
          RefreshIndicator(
            onRefresh: () async => ref.invalidate(transfersFutureProvider),
            child: transfersAsync.when(
              loading: () => const LoadingView(message: 'Loading internal transfers...'),
              error: (err, _) => ErrorView(message: err.toString(), onRetry: () => ref.invalidate(transfersFutureProvider)),
              data: (list) => list.isEmpty
                  ? const EmptyView(title: 'No Transfers Found', subtitle: 'Inter-warehouse moves will appear here')
                  : ListView.separated(
                      padding: AppSpacing.pagePadding,
                      itemCount: list.length,
                      separatorBuilder: (context, index) => const SizedBox(height: AppSpacing.sm),
                      itemBuilder: (context, i) => _buildMoveCard(list[i]),
                    ),
            ),
          ),
          // Adjustments Tab
          RefreshIndicator(
            onRefresh: () async => ref.invalidate(adjustmentsFutureProvider),
            child: adjustmentsAsync.when(
              loading: () => const LoadingView(message: 'Loading adjustments...'),
              error: (err, _) => ErrorView(message: err.toString(), onRetry: () => ref.invalidate(adjustmentsFutureProvider)),
              data: (list) => list.isEmpty
                  ? const EmptyView(title: 'No Adjustments Found', subtitle: 'Physical count reconciliations appear here')
                  : ListView.separated(
                      padding: AppSpacing.pagePadding,
                      itemCount: list.length,
                      separatorBuilder: (context, index) => const SizedBox(height: AppSpacing.sm),
                      itemBuilder: (context, i) => _buildMoveCard(list[i]),
                    ),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: AppColors.brand,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add_rounded),
        label: const Text('New Operation'),
        onPressed: () {
          if (_tabController.index == 0) {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (context) => const CreateReceiptScreen()),
            );
          } else if (_tabController.index == 1) {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (context) => const CreateDeliveryScreen()),
            );
          } else if (_tabController.index == 2) {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (context) => const CreateTransferScreen()),
            );
          } else if (_tabController.index == 3) {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (context) => const CreateAdjustmentScreen()),
            );
          }
        },
      ),
    );
  }
}
