import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_spacing.dart';
import '../../../app/theme/app_text_styles.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/system_feedback.dart';
import '../../auth/presentation/auth_provider.dart';
import '../../intelligence/presentation/intelligence_screen.dart';
import '../../warehouse/presentation/warehouse_list_screen.dart';
import '../../account/presentation/notifications_screen.dart';
import '../../account/presentation/profile_screen.dart';
import '../../account/presentation/settings_screen.dart';
import '../../account/presentation/global_search_screen.dart';

class MoreScreen extends ConsumerWidget {
  const MoreScreen({super.key});

  Widget _buildMenuItem({
    required IconData icon,
    required String title,
    required String subtitle,
    VoidCallback? onTap,
    Color? iconColor,
  }) {
    return AppCard(
      onTap: onTap,
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: (iconColor ?? AppColors.brand).withValues(alpha: 0.12),
              borderRadius: AppSpacing.borderRadiusMd,
            ),
            child: Icon(icon, color: iconColor ?? AppColors.brand, size: 20),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: AppTextStyles.labelLarge),
                Text(subtitle, style: AppTextStyles.bodySmall),
              ],
            ),
          ),
          const Icon(Icons.chevron_right_rounded, color: AppColors.inkTertiary, size: 20),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authProvider).user;

    return Scaffold(
      backgroundColor: AppColors.canvas,
      appBar: AppBar(
        title: Text('Account & Management', style: AppTextStyles.headlineLarge),
        actions: [
          IconButton(
            icon: const Icon(Icons.search_rounded),
            tooltip: 'Global Search',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const GlobalSearchScreen()),
              );
            },
          ),
        ],
      ),
      body: ListView(
        padding: AppSpacing.pagePadding,
        children: [
          // User Profile Card - Tap to open ProfileScreen
          AppCard(
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const ProfileScreen()),
              );
            },
            color: AppColors.panel,
            child: Row(
              children: [
                CircleAvatar(
                  radius: 26,
                  backgroundColor: AppColors.brand,
                  child: Text(
                    (user?.name.isNotEmpty ?? false) ? user!.name[0].toUpperCase() : 'U',
                    style: const TextStyle(fontSize: 20, color: Colors.white, fontWeight: FontWeight.bold),
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(user?.name ?? 'Warehouse Staff', style: AppTextStyles.headlineMedium),
                      Text(user?.email ?? 'staff@stocksense.com', style: AppTextStyles.bodySmall),
                      const SizedBox(height: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppColors.brand.withValues(alpha: 0.12),
                          borderRadius: AppSpacing.borderRadiusSm,
                        ),
                        child: Text(
                          (user?.role ?? 'staff').toUpperCase(),
                          style: AppTextStyles.labelSmall.copyWith(color: AppColors.brand, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right_rounded, color: AppColors.inkTertiary),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.lg),

          // Menu Sections: WAREHOUSE & INTELLIGENCE
          Text('Inventory Administration', style: AppTextStyles.labelLarge.copyWith(color: AppColors.inkSecondary)),
          const SizedBox(height: AppSpacing.sm),
          _buildMenuItem(
            icon: Icons.search_rounded,
            title: 'Global Search',
            subtitle: 'Instant search across products and ledger',
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const GlobalSearchScreen()),
              );
            },
          ),
          const SizedBox(height: AppSpacing.sm),
          _buildMenuItem(
            icon: Icons.insights_rounded,
            title: 'Inventory Intelligence',
            subtitle: 'Stock velocity, turnover, and projections',
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const IntelligenceScreen()),
              );
            },
          ),
          const SizedBox(height: AppSpacing.sm),
          _buildMenuItem(
            icon: Icons.warehouse_outlined,
            title: 'Warehouses & Locations',
            subtitle: 'Facility zones, aisles, and storage bins',
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const WarehouseListScreen()),
              );
            },
          ),
          const SizedBox(height: AppSpacing.sm),
          _buildMenuItem(
            icon: Icons.notifications_none_rounded,
            title: 'Stock Alerts & Notifications',
            subtitle: 'Reorder thresholds and system notices',
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const NotificationsScreen()),
              );
            },
          ),
          const SizedBox(height: AppSpacing.lg),

          // Menu Sections: ACCOUNT & SETTINGS
          Text('Account & Preferences', style: AppTextStyles.labelLarge.copyWith(color: AppColors.inkSecondary)),
          const SizedBox(height: AppSpacing.sm),
          _buildMenuItem(
            icon: Icons.person_outline_rounded,
            title: 'User Profile & Role',
            subtitle: 'Permissions, warehouse affiliation, credentials',
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const ProfileScreen()),
              );
            },
          ),
          const SizedBox(height: AppSpacing.sm),
          _buildMenuItem(
            icon: Icons.settings_outlined,
            title: 'System & Server Settings',
            subtitle: 'Backend API connection and offline configuration',
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const SettingsScreen()),
              );
            },
          ),
          const SizedBox(height: AppSpacing.sm),
          _buildMenuItem(
            icon: Icons.logout_rounded,
            title: 'Sign Out',
            subtitle: 'End current mobile session',
            iconColor: AppColors.statusCancelled,
            onTap: () async {
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
