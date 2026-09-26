import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_spacing.dart';
import '../../../app/theme/app_text_styles.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_text_field.dart';
import 'auth_provider.dart';

class ForgotPasswordScreen extends ConsumerStatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  ConsumerState<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends ConsumerState<ForgotPasswordScreen> {
  final _emailController = TextEditingController();
  final _otpController = TextEditingController();
  final _newPasswordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  bool _otpSent = false;
  String? _demoOtp;
  bool _obscurePassword = true;

  @override
  void dispose() {
    _emailController.dispose();
    _otpController.dispose();
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  void _handleRequestOtp() async {
    final email = _emailController.text.trim();
    if (email.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter your email address')),
      );
      return;
    }

    final otp = await ref.read(authProvider.notifier).forgotPassword(email);
    setState(() {
      _otpSent = true;
      _demoOtp = otp;
      if (otp != null) {
        _otpController.text = otp;
      }
    });

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(otp != null ? 'OTP sent! Demo code: $otp' : 'If registered, an OTP code has been sent.'),
          backgroundColor: AppColors.brandDark,
        ),
      );
    }
  }

  void _handleResetPassword() async {
    final email = _emailController.text.trim();
    final otp = _otpController.text.trim();
    final newPassword = _newPasswordController.text;
    final confirmPassword = _confirmPasswordController.text;

    if (otp.isEmpty || newPassword.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter the OTP and your new password')),
      );
      return;
    }

    if (newPassword != confirmPassword) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Passwords do not match')),
      );
      return;
    }

    final success = await ref.read(authProvider.notifier).resetPassword(
          email: email,
          otpCode: otp,
          newPassword: newPassword,
        );

    if (success && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Password reset successfully! Please sign in.'),
          backgroundColor: AppColors.statusDone,
        ),
      );
      context.go('/login');
    } else if (mounted) {
      final error = ref.read(authProvider).errorMessage ?? 'Password reset failed';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error),
          backgroundColor: AppColors.statusCancelled,
        ),
      );
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
            // Dark Navy Hero Header
            Container(
              width: double.infinity,
              padding: const EdgeInsets.only(top: 60, bottom: 36, left: 24, right: 24),
              decoration: const BoxDecoration(
                color: AppColors.navyDark,
                borderRadius: BorderRadius.only(
                  bottomLeft: Radius.circular(32),
                  bottomRight: Radius.circular(32),
                ),
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
                        onPressed: () => context.go('/login'),
                      ),
                    ],
                  ),
                  Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      color: AppColors.brand,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: const Icon(
                      Icons.lock_reset_rounded,
                      color: Colors.white,
                      size: 30,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    _otpSent ? 'Enter OTP & New Password' : 'Reset Password',
                    style: AppTextStyles.displayMedium.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    _otpSent
                        ? 'Enter the 6-digit verification code'
                        : 'Enter your registered email to receive an OTP',
                    style: AppTextStyles.bodyMedium.copyWith(
                      color: AppColors.inkTertiary,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),

            // Form
            Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (!_otpSent) ...[
                    AppTextField(
                      label: 'Email Address',
                      hintText: 'user@stocksense.com',
                      controller: _emailController,
                      keyboardType: TextInputType.emailAddress,
                      prefixIcon: const Icon(Icons.mail_outline_rounded, size: 20, color: AppColors.inkSecondary),
                    ),
                    const SizedBox(height: 24),
                    AppButton(
                      label: 'Send OTP Code',
                      onPressed: _handleRequestOtp,
                      isLoading: authState.isLoading,
                    ),
                  ] else ...[
                    if (_demoOtp != null)
                      Container(
                        padding: const EdgeInsets.all(12),
                        margin: const EdgeInsets.only(bottom: 16),
                        decoration: BoxDecoration(
                          color: AppColors.brandSubtle,
                          borderRadius: AppSpacing.borderRadiusMd,
                          border: Border.all(color: AppColors.brandLight),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.info_outline_rounded, color: AppColors.brand, size: 20),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Demo OTP Code: $_demoOtp',
                                style: AppTextStyles.labelLarge.copyWith(color: AppColors.brandDark),
                              ),
                            ),
                          ],
                        ),
                      ),
                    AppTextField(
                      label: '6-Digit OTP Code',
                      hintText: '123456',
                      controller: _otpController,
                      keyboardType: TextInputType.number,
                      prefixIcon: const Icon(Icons.pin_outlined, size: 20, color: AppColors.inkSecondary),
                    ),
                    const SizedBox(height: 16),
                    AppTextField(
                      label: 'New Password',
                      hintText: '••••••••',
                      controller: _newPasswordController,
                      obscureText: _obscurePassword,
                      prefixIcon: const Icon(Icons.lock_outline_rounded, size: 20, color: AppColors.inkSecondary),
                      suffixIcon: IconButton(
                        icon: Icon(
                          _obscurePassword ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                          size: 20,
                          color: AppColors.inkSecondary,
                        ),
                        onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                      ),
                    ),
                    const SizedBox(height: 16),
                    AppTextField(
                      label: 'Confirm New Password',
                      hintText: '••••••••',
                      controller: _confirmPasswordController,
                      obscureText: _obscurePassword,
                      prefixIcon: const Icon(Icons.lock_outline_rounded, size: 20, color: AppColors.inkSecondary),
                    ),
                    const SizedBox(height: 24),
                    AppButton(
                      label: 'Update Password',
                      onPressed: _handleResetPassword,
                      isLoading: authState.isLoading,
                    ),
                  ],
                  const SizedBox(height: 20),

                  Center(
                    child: TextButton(
                      onPressed: () => context.go('/login'),
                      child: Text(
                        'Back to Sign In',
                        style: AppTextStyles.labelLarge.copyWith(color: AppColors.brand),
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
