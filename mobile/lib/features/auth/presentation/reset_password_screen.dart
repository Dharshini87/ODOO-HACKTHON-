import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_text_styles.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_text_field.dart';
import '../../../core/widgets/system_feedback.dart';
import 'auth_provider.dart';

/// Step 3 of password-reset flow.
/// Accepts new password + confirmation, calls /api/auth/reset-password, and
/// on success navigates to /login.
///
/// The [otpCode] and [email] are passed from OtpVerificationScreen via router
/// query params. They are NEVER displayed to the user and are not re-editable.
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
  bool _obscureNew = true;
  bool _obscureConfirm = true;

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

    final success = await ref.read(authProvider.notifier).resetPassword(
          email: widget.email,
          otpCode: widget.otpCode,
          newPassword: _newPasswordController.text,
        );

    if (!mounted) return;

    if (success) {
      AppFeedback.showSuccess(
        context,
        'Password reset successful. Please sign in with your new password.',
      );
      context.go('/login');
    } else {
      final error = ref.read(authProvider).errorMessage ?? 'Password reset failed';
      AppFeedback.showError(context, error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authProvider);

    return Scaffold(
      backgroundColor: AppColors.canvas,
      body: SingleChildScrollView(
        child: Column(
          children: [
            // Hero header
            Container(
              width: double.infinity,
              padding: const EdgeInsets.only(top: 60, bottom: 40, left: 24, right: 24),
              decoration: const BoxDecoration(
                color: AppColors.navyDark,
                borderRadius: BorderRadius.only(
                  bottomLeft: Radius.circular(32),
                  bottomRight: Radius.circular(32),
                ),
              ),
              child: Column(
                children: [
                  Align(
                    alignment: Alignment.centerLeft,
                    child: IconButton(
                      icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
                      onPressed: () => context.go(
                        '/otp-verification?email=${Uri.encodeComponent(widget.email)}',
                      ),
                    ),
                  ),
                  Container(
                    width: 64,
                    height: 64,
                    decoration: BoxDecoration(
                      color: AppColors.brand,
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: const Icon(Icons.lock_outline_rounded, color: Colors.white, size: 32),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    'Create New Password',
                    style: AppTextStyles.displayMedium.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Choose a strong password for',
                    style: AppTextStyles.bodyMedium.copyWith(color: AppColors.inkTertiary),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    widget.email,
                    style: AppTextStyles.bodyMedium.copyWith(
                      color: AppColors.brand,
                      fontWeight: FontWeight.w600,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),

            Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 12),

                    // Password strength hint
                    Container(
                      padding: const EdgeInsets.all(12),
                      margin: const EdgeInsets.only(bottom: 20),
                      decoration: BoxDecoration(
                        color: AppColors.brandSubtle,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: AppColors.brandLight),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.info_outline_rounded,
                              color: AppColors.brand, size: 18),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'Use at least 6 characters with a mix of letters, numbers, and symbols.',
                              style: AppTextStyles.labelMedium
                                  .copyWith(color: AppColors.brandDark),
                            ),
                          ),
                        ],
                      ),
                    ),

                    AppTextField(
                      label: 'New Password',
                      hintText: '••••••••',
                      controller: _newPasswordController,
                      obscureText: _obscureNew,
                      prefixIcon: const Icon(
                        Icons.lock_outline_rounded,
                        size: 20,
                        color: AppColors.inkSecondary,
                      ),
                      suffixIcon: IconButton(
                        icon: Icon(
                          _obscureNew
                              ? Icons.visibility_off_outlined
                              : Icons.visibility_outlined,
                          size: 20,
                          color: AppColors.inkSecondary,
                        ),
                        onPressed: () => setState(() => _obscureNew = !_obscureNew),
                      ),
                    ),
                    const SizedBox(height: 16),
                    AppTextField(
                      label: 'Confirm New Password',
                      hintText: '••••••••',
                      controller: _confirmPasswordController,
                      obscureText: _obscureConfirm,
                      prefixIcon: const Icon(
                        Icons.lock_outline_rounded,
                        size: 20,
                        color: AppColors.inkSecondary,
                      ),
                      suffixIcon: IconButton(
                        icon: Icon(
                          _obscureConfirm
                              ? Icons.visibility_off_outlined
                              : Icons.visibility_outlined,
                          size: 20,
                          color: AppColors.inkSecondary,
                        ),
                        onPressed: () =>
                            setState(() => _obscureConfirm = !_obscureConfirm),
                      ),
                    ),
                    const SizedBox(height: 28),
                    AppButton(
                      label: 'Reset Password',
                      onPressed: _handleReset,
                      isLoading: authState.isLoading,
                      icon: Icons.check_circle_outline_rounded,
                    ),
                    const SizedBox(height: 20),
                    Center(
                      child: TextButton(
                        onPressed: () => context.go('/login'),
                        child: Text(
                          'Back to Sign In',
                          style:
                              AppTextStyles.labelLarge.copyWith(color: AppColors.brand),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
  }
}
