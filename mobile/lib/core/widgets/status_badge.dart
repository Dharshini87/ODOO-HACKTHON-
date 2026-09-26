import 'package:flutter/material.dart';
import '../../app/theme/app_colors.dart';
import '../../app/theme/app_spacing.dart';
import '../../app/theme/app_text_styles.dart';

class StatusBadge extends StatelessWidget {
  final String status;
  final double? fontSize;

  const StatusBadge({
    super.key,
    required this.status,
    this.fontSize,
  });

  @override
  Widget build(BuildContext context) {
    final normalized = status.toUpperCase().trim().replaceAll('-', '_').replaceAll(' ', '_');
    Color bg;
    Color fg;
    String display;

    // Section 33: Mobile Status Colors
    switch (normalized) {
      // Transaction: DONE -> Green
      // Inventory: NORMAL -> Green
      case 'DONE':
        bg = AppColors.statusDoneBg;
        fg = AppColors.statusDone;
        display = 'DONE';
        break;
      case 'NORMAL':
      case 'IN_STOCK':
        bg = AppColors.statusDoneBg;
        fg = AppColors.statusDone;
        display = 'NORMAL';
        break;

      // Transaction: WAITING -> Amber
      // Inventory: LOW STOCK -> Amber
      case 'WAITING':
      case 'WAITING_FOR_STOCK':
        bg = AppColors.statusWaitingBg;
        fg = AppColors.statusWaiting;
        display = 'WAITING';
        break;
      case 'LOW_STOCK':
        bg = AppColors.statusWaitingBg;
        fg = AppColors.statusWaiting;
        display = 'LOW STOCK';
        break;

      // Transaction: READY -> Teal/Blue
      case 'READY':
        bg = AppColors.statusReadyBg;
        fg = AppColors.statusReady;
        display = 'READY';
        break;

      // Transaction: CANCELED -> Gray/Red
      // Inventory: OUT OF STOCK -> Red
      case 'CANCELED':
      case 'CANCELLED':
        bg = AppColors.statusCancelledBg;
        fg = AppColors.statusCancelled;
        display = 'CANCELED';
        break;
      case 'OUT_OF_STOCK':
        bg = AppColors.statusCancelledBg;
        fg = AppColors.statusCancelled;
        display = 'OUT OF STOCK';
        break;

      // Status: LATE -> Amber
      case 'LATE':
        bg = AppColors.statusWaitingBg;
        fg = AppColors.statusWaiting;
        display = 'LATE';
        break;

      // Transaction: DRAFT -> Gray
      case 'DRAFT':
      default:
        bg = AppColors.statusDraftBg;
        fg = AppColors.statusDraft;
        display = normalized.isEmpty ? 'DRAFT' : normalized.replaceAll('_', ' ');
        break;
    }

    Widget indicator;
    if (normalized == 'LOW_STOCK' || normalized == 'LATE') {
      indicator = Icon(Icons.warning_amber_rounded, size: 12, color: fg);
    } else if (normalized == 'OUT_OF_STOCK') {
      indicator = Icon(Icons.remove_circle_outline_rounded, size: 12, color: fg);
    } else {
      indicator = Container(
        width: 6,
        height: 6,
        decoration: BoxDecoration(
          color: fg,
          shape: BoxShape.circle,
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9.0, vertical: 4.0),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: AppSpacing.borderRadiusPill,
        border: Border.all(color: fg.withValues(alpha: 0.18), width: 0.8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          indicator,
          const SizedBox(width: 5.0),
          Text(
            display,
            style: AppTextStyles.labelSmall.copyWith(
              color: fg,
              fontWeight: FontWeight.w700,
              fontSize: fontSize ?? 11,
              letterSpacing: 0.4,
            ),
          ),
        ],
      ),
    );
  }
}
