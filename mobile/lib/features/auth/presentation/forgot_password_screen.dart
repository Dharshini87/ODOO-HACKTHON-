import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_text_styles.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_text_field.dart';
import 'auth_provider.dart';

/// Step 1 of password-reset flow.
/// Shows only the email field. On submit → backend sends OTP → navigate to /otp-verification.
class ForgotPasswordScreen extends ConsumerStatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  ConsumerState<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends ConsumerState<ForgotPasswordScreen> {
  final _emailController = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  void _handleSendOtp() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    final email = _emailController.text.trim().toLowerCase();
    final authNotifier = ref.read(authProvider.notifier);

    // Call backend; returns demo_otp in dev mode, null in production.
    // Either way we navigate to OTP verification screen.
    await authNotifier.forgotPassword(email);

    if (!mounted) return;

    final authState = ref.read(authProvider);

    // Surface any rate-limit errors to the user
    if (authState.errorMessage != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(authState.errorMessage!),
          backgroundColor: AppColors.statusCancelled,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    // Navigate to OTP verification regardless (prevents email enumeration)
    context.go('/otp-verification?email=${Uri.encodeComponent(email)}');
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
                      onPressed: () => context.go('/login'),
                    ),
                  ),
                  Container(
                    width: 64,
                    height: 64,
                    decoration: BoxDecoration(
                      color: AppColors.brand,
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: const Icon(Icons.lock_reset_rounded, color: Colors.white, size: 32),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    'Reset Password',
                    style: AppTextStyles.displayMedium.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Enter your registered email address and\nwe\'ll send you a one-time code.',
                    style: AppTextStyles.bodyMedium.copyWith(color: AppColors.inkTertiary),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),

            Padding(
              padding: const EdgeInsets.all(24),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 12),
                    AppTextField(
                      label: 'Email Address',
                      hintText: 'user@stocksense.com',
                      controller: _emailController,
                      keyboardType: TextInputType.emailAddress,
                      prefixIcon: const Icon(
                        Icons.mail_outline_rounded,
                        size: 20,
                        color: AppColors.inkSecondary,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'We\'ll send a 6-digit code to this address.',
                      style: AppTextStyles.labelMedium.copyWith(color: AppColors.inkSecondary),
                    ),
                    const SizedBox(height: 28),
                    AppButton(
                      label: 'Send OTP Code',
                      onPressed: _handleSendOtp,
                      isLoading: authState.isLoading,
                      icon: Icons.send_rounded,
                    ),
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
            ),
          ],
        ),
      ),
    );
  }
}
