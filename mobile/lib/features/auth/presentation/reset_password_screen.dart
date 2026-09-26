import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_spacing.dart';
import '../../../app/theme/app_text_styles.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_text_field.dart';
import '../../../core/widgets/system_feedback.dart';
import 'auth_provider.dart';

class ResetPasswordScreen extends ConsumerStatefulWidget {
  final String email;
  final String otpCode;

  const ResetPasswordScreen({super.key, required this.email, required this.otpCode});

  @override
  ConsumerState<ResetPasswordScreen> createState() => _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends ConsumerState<ResetPasswordScreen> {
  final _newPasswordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  bool _isLoading = false;

  @override
  void dispose() {
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  void _handleReset() async {
    final newPassword = _newPasswordController.text;
    final confirm = _confirmPasswordController.text;

    if (newPassword.isEmpty || newPassword.length < 6) {
      AppFeedback.showError(context, 'Password must be at least 6 characters');
      return;
    }

    if (newPassword != confirm) {
      AppFeedback.showError(context, 'Passwords do not match');
      return;
    }

    setState(() => _isLoading = true);
    final success = await ref.read(authProvider.notifier).resetPassword(
          email: widget.email,
          otpCode: widget.otpCode,
          newPassword: newPassword,
        );
    setState(() => _isLoading = false);

    if (success && mounted) {
      AppFeedback.showSuccess(context, 'Password reset successfully! Please sign in.');
      context.go('/login');
    } else if (mounted) {
      final error = ref.read(authProvider).errorMessage ?? 'Password reset failed';
      AppFeedback.showError(context, error);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.canvas,
      appBar: AppBar(
        title: Text('Reset Password', style: AppTextStyles.headlineLarge),
      ),
      body: ListView(
        padding: AppSpacing.pagePadding,
        children: [
          const SizedBox(height: 20),
          Center(
            child: Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: AppColors.brand.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.lock_reset_rounded, size: 36, color: AppColors.brand),
            ),
          ),
          const SizedBox(height: 20),
          Text(
            'Create New Password',
            style: AppTextStyles.headlineLarge,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            'Please choose a secure new password for\n${widget.email}',
            style: AppTextStyles.bodyMedium.copyWith(color: AppColors.inkSecondary),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 32),
          AppTextField(
            controller: _newPasswordController,
            label: 'New Password',
            hintText: 'Enter at least 6 characters',
            obscureText: true,
          ),
          const SizedBox(height: AppSpacing.md),
          AppTextField(
            controller: _confirmPasswordController,
            label: 'Confirm New Password',
            hintText: 'Re-enter your new password',
            obscureText: true,
          ),
          const SizedBox(height: 24),
          AppButton(
            label: 'Update Password',
            isLoading: _isLoading,
            onPressed: _handleReset,
            icon: Icons.check_circle_outline_rounded,
          ),
        ],
      ),
    );
  }
}
