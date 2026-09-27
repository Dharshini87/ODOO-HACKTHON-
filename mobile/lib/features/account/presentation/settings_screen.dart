import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_spacing.dart';
import '../../../app/theme/app_text_styles.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/system_feedback.dart';
import '../../../core/widgets/access_denied_view.dart';
import '../../../core/providers/core_providers.dart';
import '../../auth/presentation/auth_provider.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  late final TextEditingController _urlController;

  @override
  void initState() {
    super.initState();
    _urlController = TextEditingController(text: ref.read(apiClientProvider).currentBaseUrl);
  }

  @override
  void dispose() {
    _urlController.dispose();
    super.dispose();
  }

  void _saveServerUrl() {
    final newUrl = _urlController.text.trim();
    if (newUrl.isEmpty) return;

    ref.read(apiClientProvider).updateBaseUrl(newUrl);
    ref.read(secureStorageProvider).saveBaseUrl(newUrl);
    AppFeedback.showSuccess(context, 'Backend URL updated to $newUrl');
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authProvider).user;
    if (user != null && !user.isManager) {
      return const AccessRestrictedScaffold(
        title: 'System Settings',
        message: 'Only Inventory Managers have permission to access system and server configuration.',
      );
    }

    return Scaffold(
      backgroundColor: AppColors.canvas,
      appBar: AppBar(
        title: Text('Settings', style: AppTextStyles.headlineLarge),
      ),
      body: ListView(
        padding: AppSpacing.pagePadding,
        children: [
          Text('Network & Server Configuration', style: AppTextStyles.labelLarge.copyWith(color: AppColors.inkSecondary)),
          const SizedBox(height: AppSpacing.sm),
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('FastAPI Server Base URL', style: AppTextStyles.labelSmall),
                const SizedBox(height: 6),
                TextField(
                  controller: _urlController,
                  decoration: const InputDecoration(
                    hintText: 'http://10.0.2.2:8000',
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerRight,
                  child: ElevatedButton(
                    onPressed: _saveServerUrl,
                    child: const Text('Update Server URL'),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.lg),

          Text('Operational Mode (Section 36)', style: AppTextStyles.labelLarge.copyWith(color: AppColors.inkSecondary)),
          const SizedBox(height: AppSpacing.sm),
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.cloud_sync_rounded, color: AppColors.brand, size: 22),
                    const SizedBox(width: 8),
                    Text('Online-First Inventory Architecture', style: AppTextStyles.headlineSmall),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  'In accordance with Section 36, all inventory mutating operations (Receipts, Deliveries, Transfers, Adjustments) are dispatched live to the central ledger to guarantee ACID correctness. Mutations while offline will prompt to reconnect and retry.',
                  style: AppTextStyles.bodySmall.copyWith(color: AppColors.inkSecondary),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.lg),

          Text('App Version & Diagnostics', style: AppTextStyles.labelLarge.copyWith(color: AppColors.inkSecondary)),
          const SizedBox(height: AppSpacing.sm),
          AppCard(
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('App Build', style: AppTextStyles.bodySmall),
                    Text('StockSense v1.0.0 (Production Ready)', style: AppTextStyles.labelMedium),
                  ],
                ),
                const Divider(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Target Platform', style: AppTextStyles.bodySmall),
                    Text('Flutter Cross-Platform', style: AppTextStyles.labelMedium),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
