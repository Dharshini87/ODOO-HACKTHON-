import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_spacing.dart';
import '../../../app/theme/app_text_styles.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/status_badge.dart';
import '../../auth/presentation/auth_provider.dart';
import '../../../shared/providers/inventory_providers.dart';

class AdjustmentDetailScreen extends ConsumerStatefulWidget {
  final StockMoveItem initialAdjustment;

  const AdjustmentDetailScreen({super.key, required this.initialAdjustment});

  @override
  ConsumerState<AdjustmentDetailScreen> createState() => _AdjustmentDetailScreenState();
}

class _AdjustmentDetailScreenState extends ConsumerState<AdjustmentDetailScreen> {
  late StockMoveItem _adjustment;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _adjustment = widget.initialAdjustment;
  }

  void _handleValidate() async {
    setState(() => _isLoading = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final repo = ref.read(adjustmentsRepositoryProvider);
      final validated = await repo.validateAdjustment(_adjustment.id);

      ref.invalidate(adjustmentsFutureProvider);
      ref.invalidate(stockFutureProvider);
      ref.invalidate(dashboardFutureProvider);

      if (mounted) {
        setState(() {
          _adjustment = validated;
        });
      }
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Adjustment successfully validated! Ledger entry written to database.'),
          backgroundColor: AppColors.statusDone,
        ),
      );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(
          content: Text('Adjustment validation failed: $e'),
          backgroundColor: AppColors.statusCancelled,
        ),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _handleCancel() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cancel Adjustment'),
        content: const Text('Are you sure you want to cancel this stock adjustment? No stock will be mutated.'),
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

    if (confirm != true || !mounted) return;

    setState(() => _isLoading = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final repo = ref.read(adjustmentsRepositoryProvider);
      final cancelled = await repo.cancelAdjustment(_adjustment.id);

      ref.invalidate(adjustmentsFutureProvider);

      if (mounted) {
        setState(() {
          _adjustment = cancelled;
        });
      }
      messenger.showSnackBar(
        const SnackBar(content: Text('Adjustment cancelled.')),
      );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(
          content: Text('Failed to cancel adjustment: $e'),
          backgroundColor: AppColors.statusCancelled,
        ),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authProvider);
    final user = authState.user;
    final isManager = user?.isManager ?? false;

    final sysQty = _adjustment.systemQuantity ?? _adjustment.onHand;
    final physCount = _adjustment.physicalCount ?? _adjustment.quantity;
    final diff = _adjustment.difference ?? (physCount - sysQty);

    final isDraft = _adjustment.status.toLowerCase() == 'draft';
    final isDone = _adjustment.status.toLowerCase() == 'done';
    final isCancelled = _adjustment.status.toLowerCase() == 'cancelled';

    final diffColor = diff > 0
        ? AppColors.statusDone
        : (diff < 0 ? AppColors.statusCancelled : AppColors.ink);
    final diffPrefix = diff > 0 ? '+' : '';
    final diffIcon = diff > 0
        ? Icons.trending_up_rounded
        : (diff < 0 ? Icons.trending_down_rounded : Icons.trending_flat_rounded);

    return Scaffold(
      backgroundColor: AppColors.canvas,
      appBar: AppBar(
        title: Text(_adjustment.reference, style: AppTextStyles.monoCode.copyWith(fontWeight: FontWeight.w700)),
        actions: [
          IconButton(
            tooltip: 'Copy Reference',
            icon: const Icon(Icons.copy_rounded, size: 20),
            onPressed: () {
              Clipboard.setData(ClipboardData(text: _adjustment.reference));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Reference copied to clipboard')),
              );
            },
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: AppSpacing.pagePadding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header Card
            AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('INVENTORY ADJUSTMENT', style: AppTextStyles.labelSmall.copyWith(letterSpacing: 1.1)),
                          const SizedBox(height: 2),
                          Text(_adjustment.reference, style: AppTextStyles.headlineLarge),
                        ],
                      ),
                      StatusBadge(status: _adjustment.status),
                    ],
                  ),
                  if (_adjustment.createdAt != null) ...[
                    const SizedBox(height: AppSpacing.sm),
                    Text(
                      'Created: ${_adjustment.createdAt!.split("T").first}',
                      style: AppTextStyles.labelSmall.copyWith(color: AppColors.inkTertiary),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.md),

            // Reconciliation Highlight Card (Section 23 Formula)
            AppCard(
              color: AppColors.panel,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(diffIcon, color: diffColor, size: 22),
                      const SizedBox(width: 8),
                      Text('Count Reconciliation', style: AppTextStyles.headlineMedium),
                    ],
                  ),
                  const Divider(height: 20),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      Column(
                        children: [
                          Text('System Quantity', style: AppTextStyles.labelSmall),
                          const SizedBox(height: 4),
                          Text('${sysQty.toInt()}', style: AppTextStyles.headlineLarge),
                          Text('units', style: AppTextStyles.labelSmall.copyWith(color: AppColors.inkTertiary)),
                        ],
                      ),
                      const Icon(Icons.arrow_forward_rounded, color: AppColors.inkTertiary),
                      Column(
                        children: [
                          Text('Physical Count', style: AppTextStyles.labelSmall),
                          const SizedBox(height: 4),
                          Text('${physCount.toInt()}', style: AppTextStyles.headlineLarge.copyWith(color: AppColors.brand)),
                          Text('units', style: AppTextStyles.labelSmall.copyWith(color: AppColors.inkTertiary)),
                        ],
                      ),
                      const Icon(Icons.drag_handle_rounded, color: AppColors.inkTertiary),
                      Column(
                        children: [
                          Text('Adjustment', style: AppTextStyles.labelSmall),
                          const SizedBox(height: 4),
                          Text(
                            '$diffPrefix${diff.toInt()}',
                            style: AppTextStyles.headlineLarge.copyWith(color: diffColor, fontWeight: FontWeight.w800),
                          ),
                          Text('units', style: AppTextStyles.labelSmall.copyWith(color: diffColor)),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.md),
                  // Reason Chip
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: AppColors.canvas,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: AppColors.line),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.info_outline_rounded, size: 18, color: AppColors.inkSecondary),
                        const SizedBox(width: 8),
                        Text(
                          'Declared Reason: ',
                          style: AppTextStyles.labelSmall.copyWith(fontWeight: FontWeight.w600),
                        ),
                        Text(
                          _adjustment.reason ?? 'Counting Error',
                          style: AppTextStyles.labelSmall.copyWith(color: AppColors.brand, fontWeight: FontWeight.w700),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.md),

            // Item & Location Details
            AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Location & Stock Info', style: AppTextStyles.headlineMedium),
                  const Divider(height: 16),
                  _buildDetailRow('Product', _adjustment.productName),
                  _buildDetailRow('SKU', _adjustment.sku),
                  _buildDetailRow(
                    'Location',
                    _adjustment.fromLocationName.isNotEmpty ? _adjustment.fromLocationName : 'Warehouse Floor',
                  ),
                  _buildDetailRow('Reserved Quantity', '${_adjustment.reserved.toInt()} units'),
                  _buildDetailRow('Free to Use', '${_adjustment.freeToUse.toInt()} units'),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.md),

            // Section 23 Business Rule Validation
            AppCard(
              color: physCount >= _adjustment.reserved
                  ? AppColors.statusDone.withValues(alpha: 0.06)
                  : AppColors.statusCancelled.withValues(alpha: 0.08),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        physCount >= _adjustment.reserved ? Icons.verified_rounded : Icons.warning_rounded,
                        color: physCount >= _adjustment.reserved ? AppColors.statusDone : AppColors.statusCancelled,
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Stock Constraint Validation',
                        style: AppTextStyles.labelLarge.copyWith(
                          color: physCount >= _adjustment.reserved ? AppColors.statusDone : AppColors.statusCancelled,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Rule: on_hand cannot be adjusted below reserved stock (${_adjustment.reserved.toInt()} units).',
                    style: AppTextStyles.bodySmall,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    physCount >= _adjustment.reserved
                        ? '✓ Physical count ($physCount) meets or exceeds reserved threshold.'
                        : '✗ Invalid count! Adjustment would cause on_hand ($physCount) < reserved (${_adjustment.reserved}).',
                    style: AppTextStyles.labelSmall.copyWith(
                      color: physCount >= _adjustment.reserved ? AppColors.statusDone : AppColors.statusCancelled,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.md),

            // Ledger Traceability for DONE status
            if (isDone) ...[
              AppCard(
                color: AppColors.brand.withValues(alpha: 0.05),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.history_edu_rounded, color: AppColors.brand, size: 20),
                        const SizedBox(width: 8),
                        Text('Ledger Entry Written', style: AppTextStyles.headlineMedium.copyWith(color: AppColors.brand)),
                      ],
                    ),
                    const Divider(height: 16),
                    _buildDetailRow('Movement Type', 'ADJUSTMENT'),
                    _buildDetailRow('Delta Recorded', '$diffPrefix${diff.toInt()} units'),
                    _buildDetailRow('New Running Balance', '${physCount.toInt()} units'),
                    const SizedBox(height: 4),
                    Text(
                      'No direct stock editing. Quantity reconciled through backend transaction engine.',
                      style: AppTextStyles.labelSmall.copyWith(fontStyle: FontStyle.italic),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.md),
            ],

            // Role Banner for Staff in DRAFT
            if (isDraft && !isManager) ...[
              Container(
                padding: const EdgeInsets.all(AppSpacing.md),
                decoration: BoxDecoration(
                  color: AppColors.statusWaiting.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.statusWaiting),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.lock_clock_rounded, color: AppColors.statusWaiting, size: 22),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Pending Manager Validation',
                            style: AppTextStyles.headlineMedium.copyWith(color: AppColors.statusWaiting),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Warehouse Staff can draft adjustments. An Inventory Manager must review and validate this adjustment before stock numbers update.',
                            style: AppTextStyles.bodySmall,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.md),
            ],

            // Action Buttons
            if (isDraft) ...[
              if (isManager) ...[
                AppButton(
                  label: 'Validate Adjustment',
                  icon: Icons.check_circle_rounded,
                  isLoading: _isLoading,
                  onPressed: _handleValidate,
                ),
                const SizedBox(height: AppSpacing.sm),
              ],
              OutlinedButton(
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.statusCancelled,
                  side: const BorderSide(color: AppColors.statusCancelled),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: _isLoading ? null : _handleCancel,
                child: const Text('Cancel Adjustment', style: TextStyle(fontWeight: FontWeight.w600)),
              ),
            ] else if (isDone) ...[
              Container(
                padding: const EdgeInsets.all(AppSpacing.md),
                decoration: BoxDecoration(
                  color: AppColors.statusDone.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.statusDone),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.task_alt_rounded, color: AppColors.statusDone),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Adjustment executed. Inventory quantity successfully reconciled.',
                        style: AppTextStyles.labelLarge.copyWith(color: AppColors.statusDone),
                      ),
                    ),
                  ],
                ),
              ),
            ] else if (isCancelled) ...[
              Container(
                padding: const EdgeInsets.all(AppSpacing.md),
                decoration: BoxDecoration(
                  color: AppColors.statusCancelled.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.statusCancelled),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.cancel_outlined, color: AppColors.statusCancelled),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Adjustment cancelled. No inventory adjustments were performed.',
                        style: AppTextStyles.labelLarge.copyWith(color: AppColors.statusCancelled),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: AppSpacing.xxl),
          ],
        ),
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: AppTextStyles.labelSmall),
          Flexible(
            child: Text(
              value,
              style: AppTextStyles.bodySmall.copyWith(color: AppColors.ink, fontWeight: FontWeight.w600),
              textAlign: TextAlign.end,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}
