import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_spacing.dart';
import '../../../app/theme/app_text_styles.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/status_badge.dart';
import '../../../core/widgets/system_feedback.dart';
import '../../../shared/providers/inventory_providers.dart';

class DeliveryDetailScreen extends ConsumerStatefulWidget {
  final StockMoveItem initialDelivery;

  const DeliveryDetailScreen({super.key, required this.initialDelivery});

  @override
  ConsumerState<DeliveryDetailScreen> createState() => _DeliveryDetailScreenState();
}

class _DeliveryDetailScreenState extends ConsumerState<DeliveryDetailScreen> {
  late StockMoveItem _delivery;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _delivery = widget.initialDelivery;
  }

  void _handleMarkReady() async {
    setState(() => _isLoading = true);
    try {
      final repo = ref.read(deliveriesRepositoryProvider);
      final res = await repo.markReady(_delivery.id);
      ref.invalidate(deliveriesFutureProvider);
      ref.invalidate(stockFutureProvider);
      if (mounted) {
        setState(() {
          _delivery = res;
        });
        if (res.status.toLowerCase() == 'ready') {
          AppFeedback.showSuccess(context, 'Stock reserved. Delivery is now READY!');
        } else {
          AppFeedback.showWarning(context, 'Insufficient stock. Delivery moved to WAITING FOR STOCK.');
        }
      }
    } catch (e) {
      if (mounted) {
        AppFeedback.showError(context, 'Error checking stock: $e');
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _handleValidate() async {
    setState(() => _isLoading = true);
    try {
      final repo = ref.read(deliveriesRepositoryProvider);
      final validated = await repo.validateDelivery(_delivery.id);

      ref.invalidate(deliveriesFutureProvider);
      ref.invalidate(stockFutureProvider);
      ref.invalidate(dashboardFutureProvider);

      if (mounted) {
        setState(() {
          _delivery = validated;
        });
        AppFeedback.showSuccess(context, 'Delivery validated! Inventory deducted and ledger updated.');
      }
    } catch (e) {
      if (mounted) {
        AppFeedback.showError(context, 'Validation failed: $e');
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _handleCancel() async {
    final confirm = await AppFeedback.confirm(
      context: context,
      title: 'Cancel Delivery',
      content: 'Are you sure you want to cancel this delivery? If stock was reserved, it will be returned to free stock.',
      confirmLabel: 'Yes, Cancel',
      isDestructive: true,
    );

    if (!confirm) return;

    setState(() => _isLoading = true);
    try {
      final repo = ref.read(deliveriesRepositoryProvider);
      final canceled = await repo.cancelDelivery(_delivery.id);

      ref.invalidate(deliveriesFutureProvider);
      ref.invalidate(stockFutureProvider);

      if (mounted) {
        setState(() {
          _delivery = canceled;
        });
        AppFeedback.showSuccess(context, 'Delivery has been canceled.');
      }
    } catch (e) {
      if (mounted) {
        AppFeedback.showError(context, 'Cancellation error: $e');
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final statusLower = _delivery.status.toLowerCase();
    final isDraft = statusLower == 'draft';
    final isWaiting = statusLower == 'waiting' || _delivery.isWaitingForStock;
    final isReady = statusLower == 'ready';
    final isDone = statusLower == 'done';
    final isCancelled = statusLower == 'canceled' || statusLower == 'cancelled';

    final hasSufficient = _delivery.freeToUse >= _delivery.quantity;
    final shortageVal = _delivery.shortage > 0
        ? _delivery.shortage
        : (_delivery.quantity - _delivery.freeToUse).clamp(0, 9999).toDouble();

    return Scaffold(
      backgroundColor: AppColors.canvas,
      appBar: AppBar(
        title: Text(_delivery.reference, style: AppTextStyles.headlineLarge),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: AppSpacing.md),
            child: Center(child: StatusBadge(status: _delivery.status)),
          ),
        ],
      ),
      body: ListView(
        padding: AppSpacing.pagePadding,
        children: [
          // Section 32: DELIVERY MOBILE UI SPECIFICATION CARD
          AppCard(
            color: isWaiting
                ? AppColors.statusWaitingBg.withValues(alpha: 0.3)
                : (isReady ? AppColors.brandSubtle.withValues(alpha: 0.3) : AppColors.panel),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(_delivery.productName, style: AppTextStyles.headlineLarge),
                    StatusBadge(status: _delivery.status),
                  ],
                ),
                const SizedBox(height: 2),
                Text('SKU: ${_delivery.sku}', style: AppTextStyles.monoCode),
                const Divider(height: 20),

                // Specific Section 32 Metric Requirements
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Requested:', style: AppTextStyles.labelSmall.copyWith(color: AppColors.inkTertiary)),
                          const SizedBox(height: 2),
                          Text(
                            '${_delivery.quantity.toInt()} kg',
                            style: AppTextStyles.headlineMedium.copyWith(fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Free to Use:', style: AppTextStyles.labelSmall.copyWith(color: AppColors.inkTertiary)),
                          const SizedBox(height: 2),
                          Text(
                            '${_delivery.freeToUse.toInt()} kg',
                            style: AppTextStyles.headlineMedium.copyWith(
                              color: isWaiting ? AppColors.statusCancelled : AppColors.brand,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (isWaiting && shortageVal > 0)
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Shortage:', style: AppTextStyles.labelSmall.copyWith(color: AppColors.statusCancelled)),
                            const SizedBox(height: 2),
                            Text(
                              '${shortageVal.toInt()} kg',
                              style: AppTextStyles.headlineMedium.copyWith(
                                color: AppColors.statusCancelled,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 14),

                // Section 32 Badges:
                // For available stock: "✓ Available", "READY"
                // For insufficient stock: "⚠ Insufficient Available Stock", "WAITING"
                // When stock becomes available: "✓ Stock Available", "READY"
                // After validation: "DONE"
                if (isWaiting)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: AppColors.statusCancelledBg,
                      borderRadius: AppSpacing.borderRadiusSm,
                      border: Border.all(color: AppColors.statusCancelled.withValues(alpha: 0.3)),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.warning_amber_rounded, size: 16, color: AppColors.statusCancelled),
                        const SizedBox(width: 6),
                        Text(
                          '⚠ Insufficient Available Stock',
                          style: AppTextStyles.labelMedium.copyWith(
                            color: AppColors.statusCancelled,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  )
                else if (isReady)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: AppColors.statusDoneBg,
                      borderRadius: AppSpacing.borderRadiusSm,
                      border: Border.all(color: AppColors.statusDone.withValues(alpha: 0.3)),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.check_circle_outline_rounded, size: 16, color: AppColors.statusDone),
                        const SizedBox(width: 6),
                        Text(
                          hasSufficient ? '✓ Available' : '✓ Stock Available',
                          style: AppTextStyles.labelMedium.copyWith(
                            color: AppColors.statusDone,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  )
                else if (isDone)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: AppColors.statusDoneBg,
                      borderRadius: AppSpacing.borderRadiusSm,
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.check_rounded, size: 16, color: AppColors.statusDone),
                        const SizedBox(width: 6),
                        Text(
                          'DONE (Stock Dispatched & Ledger Finalized)',
                          style: AppTextStyles.labelMedium.copyWith(
                            color: AppColors.statusDone,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.md),

          // Logistics & Route Details
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('LOGISTICS & ROUTE', style: AppTextStyles.labelSmall),
                const Divider(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Source Location', style: AppTextStyles.bodySmall),
                    Text(_delivery.fromLocationName, style: AppTextStyles.labelLarge),
                  ],
                ),
                const SizedBox(height: 6),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Customer / Destination', style: AppTextStyles.bodySmall),
                    Text(_delivery.contact ?? _delivery.toLocationName, style: AppTextStyles.labelLarge),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.md),

          // Inventory Ledger State Breakdown
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('INVENTORY STATE', style: AppTextStyles.labelSmall),
                const Divider(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    Column(
                      children: [
                        Text('ON HAND', style: AppTextStyles.labelSmall.copyWith(fontSize: 10)),
                        const SizedBox(height: 2),
                        Text('${_delivery.onHand.toInt()} kg', style: AppTextStyles.headlineSmall),
                      ],
                    ),
                    Column(
                      children: [
                        Text('RESERVED', style: AppTextStyles.labelSmall.copyWith(fontSize: 10, color: AppColors.statusWaiting)),
                        const SizedBox(height: 2),
                        Text('${_delivery.reserved.toInt()} kg', style: AppTextStyles.headlineSmall.copyWith(color: AppColors.statusWaiting)),
                      ],
                    ),
                    Column(
                      children: [
                        Text('FREE TO USE', style: AppTextStyles.labelSmall.copyWith(fontSize: 10, color: AppColors.brand)),
                        const SizedBox(height: 2),
                        Text('${_delivery.freeToUse.toInt()} kg', style: AppTextStyles.headlineSmall.copyWith(color: AppColors.brand)),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.lg),

          // Action Buttons
          if (isDraft) ...[
            AppButton(
              label: 'Check Stock & Mark Ready',
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
              label: const Text('Validate Delivery Directly'),
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
              label: const Text('Cancel Delivery'),
              onPressed: _isLoading ? null : _handleCancel,
            ),
          ] else if (isWaiting) ...[
            AppButton(
              label: 'Re-Check Stock Availability',
              onPressed: _handleMarkReady,
              isLoading: _isLoading,
              icon: Icons.refresh_rounded,
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
              label: const Text('Cancel Delivery'),
              onPressed: _isLoading ? null : _handleCancel,
            ),
          ] else if (isReady) ...[
            AppButton(
              label: 'Confirm Dispatch / Validate',
              onPressed: _handleValidate,
              isLoading: _isLoading,
              icon: Icons.local_shipping_rounded,
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
              label: const Text('Cancel Delivery (Release Reservation)'),
              onPressed: _isLoading ? null : _handleCancel,
            ),
          ] else if (isCancelled) ...[
            Center(
              child: Text(
                'This delivery order has been cancelled.',
                style: AppTextStyles.bodySmall.copyWith(color: AppColors.statusCancelled),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
