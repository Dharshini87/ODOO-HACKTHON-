import 'package:flutter/material.dart';
import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_spacing.dart';
import '../../../app/theme/app_text_styles.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/app_button.dart';
import 'notifications_screen.dart';

class NotificationDetailScreen extends StatelessWidget {
  final NotificationItem notification;

  const NotificationDetailScreen({super.key, required this.notification});

  @override
  Widget build(BuildContext context) {
    Color iconColor = AppColors.brand;
    IconData iconData = Icons.info_outline_rounded;

    if (notification.type == 'warning') {
      iconColor = AppColors.amber;
      iconData = Icons.warning_amber_rounded;
    } else if (notification.type == 'success') {
      iconColor = AppColors.statusDone;
      iconData = Icons.check_circle_outline_rounded;
    }

    return Scaffold(
      backgroundColor: AppColors.canvas,
      appBar: AppBar(
        title: Text('Notification Details', style: AppTextStyles.headlineLarge),
      ),
      body: ListView(
        padding: AppSpacing.pagePadding,
        children: [
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: iconColor.withValues(alpha: 0.12),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(iconData, color: iconColor, size: 24),
                    ),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(notification.title, style: AppTextStyles.headlineMedium),
                          const SizedBox(height: 2),
                          Text(notification.timestamp, style: AppTextStyles.bodySmall),
                        ],
                      ),
                    ),
                  ],
                ),
                const Divider(height: 24),
                Text(
                  notification.message,
                  style: AppTextStyles.bodyMedium,
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.xl),
          AppButton(
            label: 'Dismiss Notification',
            variant: AppButtonVariant.outline,
            onPressed: () => Navigator.pop(context),
          ),
        ],
      ),
    );
  }
}
