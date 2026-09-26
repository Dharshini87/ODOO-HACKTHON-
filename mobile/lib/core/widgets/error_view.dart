import 'package:flutter/material.dart';
import '../../app/theme/app_colors.dart';
import '../../app/theme/app_spacing.dart';
import '../../app/theme/app_text_styles.dart';
import 'app_button.dart';

class ErrorView extends StatelessWidget {
  final String message;
  final String? title;
  final VoidCallback? onRetry;
  final IconData? icon;

  const ErrorView({
    super.key,
    required this.message,
    this.title,
    this.onRetry,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final displayTitle = title ?? 'Something went wrong';
    final isOffline = displayTitle.toLowerCase().contains('internet') ||
        displayTitle.toLowerCase().contains('connection') ||
        message.toLowerCase().contains('connection');

    return Center(
      child: Padding(
        padding: AppSpacing.pagePadding,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: isOffline
                    ? AppColors.amber.withValues(alpha: 0.15)
                    : AppColors.statusCancelled.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(
                icon ?? (isOffline ? Icons.wifi_off_rounded : Icons.error_outline_rounded),
                color: isOffline ? AppColors.amber : AppColors.statusCancelled,
                size: 28,
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              displayTitle,
              style: AppTextStyles.headlineMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              message,
              style: AppTextStyles.bodyMedium.copyWith(color: AppColors.inkSecondary),
              textAlign: TextAlign.center,
            ),
            if (onRetry != null) ...[
              const SizedBox(height: AppSpacing.lg),
              AppButton(
                label: 'Retry',
                onPressed: onRetry,
                variant: AppButtonVariant.outline,
                icon: Icons.refresh_rounded,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
