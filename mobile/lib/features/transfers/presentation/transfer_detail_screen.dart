import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_spacing.dart';
import '../../../app/theme/app_text_styles.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/status_badge.dart';
import '../../../shared/providers/inventory_providers.dart';

class TransferDetailScreen extends ConsumerStatefulWidget {
  final StockMoveItem initialTransfer;

  const TransferDetailScreen({super.key, required this.initialTransfer});

  @override
  ConsumerState<TransferDetailScreen> createState() => _TransferDetailScreenState();
}

class _TransferDetailScreenState extends ConsumerState<TransferDetailScreen> {
  late StockMoveItem _transfer;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _transfer = widget.initialTransfer;
  }

  void _handleMarkReady() async {
    setState(() => _isLoading = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final repo = ref.read(transfersRepositoryProvider);
      final res = await repo.markReady(_transfer.id);
      ref.invalidate(transfersFutureProvider);
      ref.invalidate(stockFutureProvider);
      if (mounted) {
        setState(() {
          _transfer = res;
        });
      }
      messenger.showSnackBar(
        const SnackBar(content: Text('Transfer verified against free-to-use stock and marked READY')),
      );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('Validation error: $e'), backgroundColor: AppColors.statusCancelled),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _handleValidate() async {
    setState(() => _isLoading = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final repo = ref.read(transfersRepositoryProvider);
      final validated = await repo.validateTransfer(_transfer.id);

      ref.invalidate(transfersFutureProvider);
      ref.invalidate(stockFutureProvider);
      ref.invalidate(dashboardFutureProvider);

      if (mounted) {
        setState(() {
          _transfer = validated;
        });
      }
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Transfer executed atomically! TRANSFER_OUT and TRANSFER_IN written.'),
          backgroundColor: AppColors.statusDone,
        ),
      );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('Transfer validation failed: $e'), backgroundColor: AppColors.statusCancelled),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _handleCancel() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cancel Transfer'),
        content: const Text('Are you sure you want to cancel this transfer order?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('No')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: AppColors.statusCancelled),
            child: const Text('Yes, Cancel'),
          ),
        ],
      ),
    );

    if (confirm != true) return;
    if (!mounted) return;

    setState(() => _isLoading = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final repo = ref.read(transfersRepositoryProvider);
      final canceled = await repo.cancelTransfer(_transfer.id);

      ref.invalidate(transfersFutureProvider);
      ref.invalidate(stockFutureProvider);

      if (mounted) {
        setState(() {
          _transfer = canceled;
        });
      }
      messenger.showSnackBar(
        const SnackBar(content: Text('Transfer has been canceled.')),
      );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('Cancellation error: $e'), backgroundColor: AppColors.statusCancelled),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final statusLower = _transfer.status.toLowerCase();
    final isDraft = statusLower == 'draft';
    final isReady = statusLower == 'ready';
    final isDone = statusLower == 'done';
    final isCancelled = statusLower == 'canceled' || statusLower == 'cancelled';

    return Scaffold(
      backgroundColor: AppColors.canvas,
      appBar: AppBar(
        title: Text(_transfer.reference, style: AppTextStyles.headlineLarge),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: AppSpacing.md),
            child: Center(child: StatusBadge(status: _transfer.status)),
          ),
        ],
      ),
      body: ListView(
        padding: AppSpacing.pagePadding,
        children: [
          // ROUTE CARD
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('INTERNAL TRANSFER ROUTE', style: AppTextStyles.labelSmall),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('SOURCE LOCATION', style: AppTextStyles.labelSmall.copyWith(fontSize: 10)),
                          const SizedBox(height: 2),
                          Text(_transfer.fromLocationName, style: AppTextStyles.headlineMedium),
                          Text('on_hand -= ${_transfer.quantity.toInt()}', style: AppTextStyles.monoCode.copyWith(color: AppColors.statusCancelled)),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: AppColors.brand.withValues(alpha: 0.1),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.arrow_forward_rounded, color: AppColors.brand, size: 24),
                    ),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text('DESTINATION LOCATION', style: AppTextStyles.labelSmall.copyWith(fontSize: 10)),
                          const SizedBox(height: 2),
                          Text(_transfer.toLocationName, style: AppTextStyles.headlineMedium),
                          Text('on_hand += ${_transfer.quantity.toInt()}', style: AppTextStyles.monoCode.copyWith(color: AppColors.statusDone)),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.md),

          // PRODUCT & QUANTITY CARD
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('ITEM DETAILS', style: AppTextStyles.labelSmall),
                    Text('SKU: ${_transfer.sku}', style: AppTextStyles.monoCode),
                  ],
                ),
                const SizedBox(height: 8),
                Text(_transfer.productName, style: AppTextStyles.headlineMedium),
                const Divider(height: 20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Transfer Quantity', style: AppTextStyles.bodyMedium),
                    Text(
                      '${_transfer.quantity.toInt()} units',
                      style: AppTextStyles.headlineLarge.copyWith(color: AppColors.brand),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  'Section 22 Rule: Transfer must use FREE TO USE stock only. Reserved inventory cannot be transferred.',
                  style: AppTextStyles.bodySmall.copyWith(color: AppColors.inkTertiary, fontStyle: FontStyle.italic),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.md),

          // ATOMIC DUAL-LEDGER IMPACT CARD (WHEN DONE)
          if (isDone) ...[
            AppCard(
              color: AppColors.statusDone.withValues(alpha: 0.08),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.check_circle_rounded, color: AppColors.statusDone, size: 22),
                      const SizedBox(width: 8),
                      Text(
                        'Atomic Transfer Complete',
                        style: AppTextStyles.labelLarge.copyWith(color: AppColors.statusDone, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                  const Divider(height: 20),
                  // TRANSFER_OUT
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('LEDGER OUTFLOW (SOURCE)', style: AppTextStyles.labelSmall),
                          Text('-${_transfer.quantity.toInt()} units', style: AppTextStyles.headlineSmall.copyWith(color: AppColors.statusCancelled)),
                        ],
                      ),
                      Text('TRANSFER_OUT', style: AppTextStyles.monoCode.copyWith(fontWeight: FontWeight.bold)),
                    ],
                  ),
                  const SizedBox(height: 12),
                  // TRANSFER_IN
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('LEDGER INFLOW (DESTINATION)', style: AppTextStyles.labelSmall),
                          Text('+${_transfer.quantity.toInt()} units', style: AppTextStyles.headlineSmall.copyWith(color: AppColors.statusDone)),
                        ],
                      ),
                      Text('TRANSFER_IN', style: AppTextStyles.monoCode.copyWith(fontWeight: FontWeight.bold)),
                    ],
                  ),
                  if (_transfer.doneAt != null) ...[
                    const Divider(height: 20),
                    Text('Executed At: ${_transfer.doneAt}', style: AppTextStyles.bodySmall),
                  ],
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.xl),
          ],

          // Action Buttons
          if (isDraft) ...[
            const SizedBox(height: AppSpacing.lg),
            AppButton(
              label: 'Verify Free Stock & Mark Ready',
              onPressed: _handleMarkReady,
              isLoading: _isLoading,
              icon: Icons.assignment_turned_in_outlined,
            ),
            const SizedBox(height: AppSpacing.sm),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.brand,
                side: const BorderSide(color: AppColors.brand),
                minimumSize: const Size(double.infinity, 48),
                shape: RoundedRectangleBorder(borderRadius: AppSpacing.borderRadiusMd),
              ),
              icon: const Icon(Icons.check_circle_outline_rounded, size: 18),
              label: const Text('Validate & Execute Transfer'),
              onPressed: _isLoading ? null : _handleValidate,
            ),
            const SizedBox(height: AppSpacing.sm),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.statusCancelled,
                side: const BorderSide(color: AppColors.statusCancelled),
                minimumSize: const Size(double.infinity, 48),
                shape: RoundedRectangleBorder(borderRadius: AppSpacing.borderRadiusMd),
              ),
              icon: const Icon(Icons.cancel_outlined, size: 18),
              label: const Text('Cancel Transfer'),
              onPressed: _isLoading ? null : _handleCancel,
            ),
          ] else if (isReady) ...[
            const SizedBox(height: AppSpacing.lg),
            AppButton(
              label: 'Validate & Execute Transfer',
              onPressed: _handleValidate,
              isLoading: _isLoading,
              icon: Icons.sync_alt_rounded,
            ),
            const SizedBox(height: AppSpacing.sm),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.statusCancelled,
                side: const BorderSide(color: AppColors.statusCancelled),
                minimumSize: const Size(double.infinity, 48),
                shape: RoundedRectangleBorder(borderRadius: AppSpacing.borderRadiusMd),
              ),
              icon: const Icon(Icons.cancel_outlined, size: 18),
              label: const Text('Cancel Transfer'),
              onPressed: _isLoading ? null : _handleCancel,
            ),
          ] else if (isCancelled) ...[
            const SizedBox(height: AppSpacing.md),
            Center(
              child: Text('This transfer order has been canceled.', style: AppTextStyles.bodySmall.copyWith(color: AppColors.statusCancelled)),
            ),
          ],
        ],
      ),
    );
  }
}
