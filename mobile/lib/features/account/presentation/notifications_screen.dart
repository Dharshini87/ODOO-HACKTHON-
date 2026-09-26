import 'package:flutter/material.dart';
import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_spacing.dart';
import '../../../app/theme/app_text_styles.dart';
import '../../../core/widgets/app_card.dart';
import 'notification_detail_screen.dart';

class NotificationItem {
  final String id;
  final String title;
  final String message;
  final String timestamp;
  final String type; // 'warning', 'info', 'success'
  final bool isRead;

  NotificationItem({
    required this.id,
    required this.title,
    required this.message,
    required this.timestamp,
    this.type = 'info',
    this.isRead = false,
  });
}

class NotificationsScreen extends StatelessWidget {
  const NotificationsScreen({super.key});

  static final List<NotificationItem> _sampleNotifications = [
    NotificationItem(
      id: '1',
      title: 'Low Stock Alert: Steel Rod',
      message: 'On-hand quantity for Steel Rod (SR-001) has dropped below the reorder point of 10.0 kg.',
      timestamp: '10 mins ago',
      type: 'warning',
    ),
    NotificationItem(
      id: '2',
      title: 'Outbound Delivery Waiting for Stock',
      message: 'Delivery WH/OUT/0002 cannot transition to READY because available stock is insufficient.',
      timestamp: '1 hour ago',
      type: 'warning',
    ),
    NotificationItem(
      id: '3',
      title: 'Inbound Receipt Validated',
      message: 'Receipt WH/IN/0001 has been validated by warehouse manager. 100 kg added to on-hand inventory.',
      timestamp: '3 hours ago',
      type: 'success',
      isRead: true,
    ),
    NotificationItem(
      id: '4',
      title: 'Database Synchronization Complete',
      message: 'Periodic inventory ledger reconciliation completed without errors.',
      timestamp: 'Yesterday',
      type: 'info',
      isRead: true,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.canvas,
      appBar: AppBar(
        title: Text('Notifications', style: AppTextStyles.headlineLarge),
      ),
      body: ListView.separated(
        padding: AppSpacing.pagePadding,
        itemCount: _sampleNotifications.length,
        separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.sm),
        itemBuilder: (context, i) {
          final notif = _sampleNotifications[i];
          Color iconColor = AppColors.brand;
          IconData iconData = Icons.info_outline_rounded;

          if (notif.type == 'warning') {
            iconColor = AppColors.amber;
            iconData = Icons.warning_amber_rounded;
          } else if (notif.type == 'success') {
            iconColor = AppColors.statusDone;
            iconData = Icons.check_circle_outline_rounded;
          }

          return AppCard(
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => NotificationDetailScreen(notification: notif),
                ),
              );
            },
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: iconColor.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(iconData, color: iconColor, size: 20),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Text(
                              notif.title,
                              style: AppTextStyles.labelLarge.copyWith(
                                fontWeight: notif.isRead ? FontWeight.w500 : FontWeight.bold,
                              ),
                            ),
                          ),
                          Text(notif.timestamp, style: AppTextStyles.labelSmall.copyWith(fontSize: 10, color: AppColors.inkTertiary)),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        notif.message,
                        style: AppTextStyles.bodySmall,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
