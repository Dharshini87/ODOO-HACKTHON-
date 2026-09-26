import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_spacing.dart';
import '../../../app/theme/app_text_styles.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/status_badge.dart';
import '../../../shared/providers/inventory_providers.dart';
import 'physical_receipt_verification_card.dart';


class ReceiptDetailScreen extends ConsumerStatefulWidget {
  final StockMoveItem initialReceipt;

  const ReceiptDetailScreen({super.key, required this.initialReceipt});

  @override
  ConsumerState<ReceiptDetailScreen> createState() => _ReceiptDetailScreenState();
}

class _ReceiptDetailScreenState extends ConsumerState<ReceiptDetailScreen> {
  late StockMoveItem _receipt;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _receipt = widget.initialReceipt;
  }

  void _handleMarkReady() async {
    setState(() => _isLoading = true);
    try {
      final repo = ref.read(receiptsRepositoryProvider);
      final res = await repo.markReady(_receipt.id);
      ref.invalidate(receiptsFutureProvider);
      ref.invalidate(stockFutureProvider);
      if (mounted) {
        setState(() {
          _receipt = res;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Receipt marked as READY')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: AppColors.statusCancelled),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _handleValidate() async {
    setState(() => _isLoading = true);
    try {
      final repo = ref.read(receiptsRepositoryProvider);
      final validated = await repo.validateReceipt(_receipt.id);

      ref.invalidate(receiptsFutureProvider);
      ref.invalidate(stockFutureProvider);
      ref.invalidate(dashboardFutureProvider);

      if (mounted) {
        setState(() {
          _receipt = validated;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Stock received successfully! (on_hand increased)'),
            backgroundColor: AppColors.statusDone,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Validation error: $e'), backgroundColor: AppColors.statusCancelled),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _handleCancel() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cancel Receipt'),
        content: const Text('Are you sure you want to cancel this receipt? This action cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Keep Receipt')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.statusCancelled),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Cancel Receipt'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() => _isLoading = true);
    try {
      final repo = ref.read(receiptsRepositoryProvider);
      final canceled = await repo.cancelReceipt(_receipt.id);
      ref.invalidate(receiptsFutureProvider);

      if (mounted) {
        setState(() {
          _receipt = canceled;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Receipt canceled'), backgroundColor: AppColors.statusCancelled),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Cancellation error: $e'), backgroundColor: AppColors.statusCancelled),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final status = _receipt.status.toLowerCase();
    final isDraft = status == 'draft';
    final isReady = status == 'ready';
    final isDone = status == 'done';
    final isCanceled = status == 'cancelled' || status == 'canceled';

    return Scaffold(
      backgroundColor: AppColors.canvas,
      appBar: AppBar(
        title: Text('Receipt Detail', style: AppTextStyles.headlineLarge),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Center(child: StatusBadge(status: _receipt.status)),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: AppSpacing.pagePadding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Reference Header Card
            AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(_receipt.reference, style: AppTextStyles.displaySmall.copyWith(fontSize: 22)),
                      StatusBadge(status: _receipt.status),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text('Supplier / Vendor: ${_receipt.contact ?? "Vendor"}', style: AppTextStyles.headlineMedium),
                  const SizedBox(height: 4),
                  Text('Destination Location: ${_receipt.toLocationName}', style: AppTextStyles.bodyMedium),
                  if (_receipt.createdAt != null) ...[
                    const SizedBox(height: 4),
                    Text('Created: ${_receipt.createdAt}', style: AppTextStyles.bodySmall),
                  ],
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.md),

            // Item Details Card
            Text('Received Items', style: AppTextStyles.headlineSmall),
            const SizedBox(height: 8),
            AppCard(
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
                        Text(_receipt.productName, style: AppTextStyles.headlineMedium),
                        Text('SKU: ${_receipt.sku}', style: AppTextStyles.bodySmall),
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text('Quantity', style: AppTextStyles.labelSmall),
                      Text(
                        '+${_receipt.quantity.toInt()} units',
                        style: AppTextStyles.headlineMedium.copyWith(color: AppColors.brand, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.md),

            // Physical Receipt Verification (Sections 26-31)
            PhysicalReceiptVerificationCard(
              receiptId: _receipt.id,
              reference: _receipt.reference,
              productName: _receipt.productName,
              quantity: _receipt.quantity,
              supplier: _receipt.contact,
              isImmutable: isDone || isCanceled,
            ),
            const SizedBox(height: AppSpacing.md),

            // Ledger Impact Card (If DONE)
            if (isDone) ...[

              Text('Audit Ledger Record (Section 19)', style: AppTextStyles.headlineSmall),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.statusDoneBg,
                  borderRadius: AppSpacing.borderRadiusMd,
                  border: Border.all(color: AppColors.statusDone.withValues(alpha: 0.3)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.check_circle_rounded, color: AppColors.statusDone, size: 20),
                        const SizedBox(width: 8),
                        Text(
                          'Stock Successfully Updated (on_hand increased)',
                          style: AppTextStyles.labelLarge.copyWith(color: AppColors.statusDone, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                    const Divider(height: 20),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('QUANTITY CHANGE', style: AppTextStyles.labelSmall),
                            Text('+${_receipt.quantity.toInt()} units', style: AppTextStyles.headlineSmall.copyWith(color: AppColors.statusDone)),
                          ],
                        ),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text('MOVEMENT TYPE', style: AppTextStyles.labelSmall),
                            Text('RECEIPT', style: AppTextStyles.headlineSmall.copyWith(color: AppColors.ink)),
                          ],
                        ),
                      ],
                    ),
                    if (_receipt.doneAt != null) ...[
                      const SizedBox(height: 8),
                      Text('Completed At: ${_receipt.doneAt}', style: AppTextStyles.bodySmall),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.xl),
            ],

            // Action Buttons based on state
            if (isDraft) ...[
              const SizedBox(height: AppSpacing.lg),
              AppButton(
                label: 'Mark as Ready',
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
                label: const Text('Validate / Receive Directly'),
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
                label: const Text('Cancel Receipt'),
                onPressed: _isLoading ? null : _handleCancel,
              ),
            ] else if (isReady) ...[
              const SizedBox(height: AppSpacing.lg),
              AppButton(
                label: 'Confirm Receiving Goods',
                onPressed: _handleValidate,
                isLoading: _isLoading,
                icon: Icons.inventory_rounded,
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
                label: const Text('Cancel Receipt'),
                onPressed: _isLoading ? null : _handleCancel,
              ),
            ] else if (isDone) ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 12),
                alignment: Alignment.center,
                child: Text(
                  'This completed receipt is immutable.',
                  style: AppTextStyles.bodySmall.copyWith(color: AppColors.inkTertiary),
                ),
              ),
            ] else if (isCanceled) ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 12),
                alignment: Alignment.center,
                child: Text(
                  'This receipt was canceled.',
                  style: AppTextStyles.bodySmall.copyWith(color: AppColors.statusCancelled),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
