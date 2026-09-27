import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../app/theme/app_colors.dart';
import '../../app/theme/app_spacing.dart';
import '../../app/theme/app_text_styles.dart';
import 'app_button.dart';
import 'app_card.dart';

class AccessDeniedView extends StatelessWidget {
  final String title;
  final String message;
  final VoidCallback? onReturn;

  const AccessDeniedView({
    super.key,
    this.title = 'Access Restricted',
    this.message = 'This management action requires Inventory Manager permissions.',
    this.onReturn,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: AppSpacing.pagePadding,
        child: AppCard(
          color: AppColors.panel,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 60,
                height: 60,
                decoration: BoxDecoration(
                  color: AppColors.statusCancelled.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.shield_outlined,
                  color: AppColors.statusCancelled,
                  size: 32,
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              Text(
                title,
                style: AppTextStyles.headlineMedium.copyWith(fontWeight: FontWeight.w700),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                message,
                style: AppTextStyles.bodyMedium.copyWith(color: AppColors.inkSecondary),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: AppSpacing.lg),
              AppButton(
                label: 'Return to Home',
                variant: AppButtonVariant.outline,
                icon: Icons.arrow_back_rounded,
                onPressed: onReturn ??
                    () {
                      if (Navigator.canPop(context)) {
                        Navigator.pop(context);
                      } else {
                        context.go('/home');
                      }
                    },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class AccessRestrictedScaffold extends StatelessWidget {
  final String title;
  final String message;

  const AccessRestrictedScaffold({
    super.key,
    this.title = 'Access Restricted',
    this.message = 'This management action requires Inventory Manager permissions.',
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.canvas,
      appBar: AppBar(
        title: Text(title, style: AppTextStyles.headlineLarge),
      ),
      body: AccessDeniedView(
        title: 'Access Restricted',
        message: message,
      ),
    );
  }
}
