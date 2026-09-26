import 'package:flutter/material.dart';
import '../../app/theme/app_colors.dart';
import '../../app/theme/app_spacing.dart';
import '../../app/theme/app_text_styles.dart';
import 'status_badge.dart';

class AppFeedback {
  AppFeedback._();

  static void showSuccess(BuildContext context, String message) {
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: AppColors.statusDone,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: AppSpacing.borderRadiusSm),
        content: Row(
          children: [
            const Icon(Icons.check_circle_rounded, color: Colors.white, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      ),
    );
  }

  static void showError(BuildContext context, String message) {
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: AppColors.statusCancelled,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: AppSpacing.borderRadiusSm),
        content: Row(
          children: [
            const Icon(Icons.error_outline_rounded, color: Colors.white, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w500),
              ),
            ),
          ],
        ),
      ),
    );
  }

  static void showWarning(BuildContext context, String message) {
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: AppColors.amber,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: AppSpacing.borderRadiusSm),
        content: Row(
          children: [
            const Icon(Icons.warning_amber_rounded, color: Colors.white, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w500),
              ),
            ),
          ],
        ),
      ),
    );
  }

  static Future<bool> confirm({
    required BuildContext context,
    required String title,
    required String content,
    String confirmLabel = 'Confirm',
    String cancelLabel = 'Cancel',
    bool isDestructive = false,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title, style: AppTextStyles.headlineMedium),
        content: Text(content, style: AppTextStyles.bodyMedium),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(cancelLabel, style: AppTextStyles.labelMedium),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: isDestructive ? AppColors.statusCancelled : AppColors.brand,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(confirmLabel),
          ),
        ],
      ),
    );
    return result ?? false;
  }
}

/// Section 32 & System Insufficient Stock State
class InsufficientStockCard extends StatelessWidget {
  final String productName;
  final double requested;
  final double freeToUse;
  final double shortage;
  final String unitOfMeasure;

  const InsufficientStockCard({
    super.key,
    required this.productName,
    required this.requested,
    required this.freeToUse,
    required this.shortage,
    this.unitOfMeasure = 'kg',
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.statusCancelledBg.withValues(alpha: 0.5),
        borderRadius: AppSpacing.borderRadiusMd,
        border: Border.all(color: AppColors.statusCancelled.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                productName,
                style: AppTextStyles.headlineSmall.copyWith(fontWeight: FontWeight.bold),
              ),
              const StatusBadge(status: 'WAITING'),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Requested:\n${requested.toInt()} $unitOfMeasure',
            style: AppTextStyles.bodySmall,
          ),
          const SizedBox(height: 4),
          Text(
            'Free to Use:\n${freeToUse.toInt()} $unitOfMeasure',
            style: AppTextStyles.bodySmall,
          ),
          const SizedBox(height: 4),
          Text(
            'Shortage:\n${shortage.toInt()} $unitOfMeasure',
            style: AppTextStyles.bodySmall.copyWith(color: AppColors.statusCancelled, fontWeight: FontWeight.bold),
          ),
          const Divider(height: 16),
          Row(
            children: [
              const Icon(Icons.warning_amber_rounded, color: AppColors.statusCancelled, size: 18),
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
        ],
      ),
    );
  }
}
