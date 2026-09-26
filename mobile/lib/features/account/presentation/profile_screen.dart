import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_spacing.dart';
import '../../../app/theme/app_text_styles.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/system_feedback.dart';
import '../../auth/presentation/auth_provider.dart';

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authProvider).user;

    return Scaffold(
      backgroundColor: AppColors.canvas,
      appBar: AppBar(
        title: Text('Account Profile', style: AppTextStyles.headlineLarge),
      ),
      body: ListView(
        padding: AppSpacing.pagePadding,
        children: [
          // Profile Card
          AppCard(
            child: Column(
              children: [
                CircleAvatar(
                  radius: 40,
                  backgroundColor: AppColors.brand,
                  child: Text(
                    (user?.name.isNotEmpty ?? false) ? user!.name[0].toUpperCase() : 'U',
                    style: const TextStyle(fontSize: 32, color: Colors.white, fontWeight: FontWeight.bold),
                  ),
                ),
                const SizedBox(height: 12),
                Text(user?.name ?? 'Warehouse Staff', style: AppTextStyles.headlineLarge),
                const SizedBox(height: 4),
                Text(user?.email ?? 'staff@stocksense.com', style: AppTextStyles.bodyMedium),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.brand.withValues(alpha: 0.12),
                    borderRadius: AppSpacing.borderRadiusSm,
                  ),
                  child: Text(
                    (user?.role ?? 'STAFF').toUpperCase(),
                    style: AppTextStyles.labelSmall.copyWith(color: AppColors.brandDark, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.md),

          // Security & Access Details
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('SECURITY & PERMISSIONS', style: AppTextStyles.labelSmall),
                const Divider(height: 20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('User Role Access', style: AppTextStyles.bodySmall),
                    Text(
                      user?.role == 'manager' ? 'Full Manager Permissions' : 'Operational Staff Permissions',
                      style: AppTextStyles.labelMedium,
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Default Warehouse', style: AppTextStyles.bodySmall),
                    Text('Main Warehouse', style: AppTextStyles.labelMedium),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Session Status', style: AppTextStyles.bodySmall),
                    Row(
                      children: [
                        const Icon(Icons.circle, size: 8, color: AppColors.statusDone),
                        const SizedBox(width: 6),
                        Text('Online / Authenticated', style: AppTextStyles.labelSmall.copyWith(color: AppColors.statusDone, fontWeight: FontWeight.bold)),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.xl),

          AppButton(
            label: 'Sign Out',
            variant: AppButtonVariant.outline,
            icon: Icons.logout_rounded,
            onPressed: () async {
              final confirm = await AppFeedback.confirm(
                context: context,
                title: 'Sign Out',
                content: 'Are you sure you want to end your StockSense session?',
                confirmLabel: 'Sign Out',
                isDestructive: true,
              );
              if (confirm) {
                await ref.read(authProvider.notifier).logout();
                if (context.mounted) context.go('/login');
              }
            },
          ),
        ],
      ),
    );
  }
}
