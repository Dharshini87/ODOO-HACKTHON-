import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_spacing.dart';
import '../../../app/theme/app_text_styles.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_text_field.dart';
import '../../../core/widgets/system_feedback.dart';
import 'reset_password_screen.dart';

class OtpVerificationScreen extends ConsumerStatefulWidget {
  final String email;

  const OtpVerificationScreen({super.key, required this.email});

  @override
  ConsumerState<OtpVerificationScreen> createState() => _OtpVerificationScreenState();
}

class _OtpVerificationScreenState extends ConsumerState<OtpVerificationScreen> {
  final _otpController = TextEditingController();

  @override
  void dispose() {
    _otpController.dispose();
    super.dispose();
  }

  void _verifyOtp() {
    final otp = _otpController.text.trim();
    if (otp.isEmpty || otp.length < 4) {
      AppFeedback.showError(context, 'Please enter a valid verification code');
      return;
    }

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ResetPasswordScreen(email: widget.email, otpCode: otp),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.canvas,
      appBar: AppBar(
        title: Text('OTP Verification', style: AppTextStyles.headlineLarge),
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
              child: const Icon(Icons.mark_email_read_outlined, size: 36, color: AppColors.brand),
            ),
          ),
          const SizedBox(height: 20),
          Text(
            'Enter Verification Code',
            style: AppTextStyles.headlineLarge,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            'We sent a 6-digit verification code to\n${widget.email}',
            style: AppTextStyles.bodyMedium.copyWith(color: AppColors.inkSecondary),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 32),
          AppTextField(
            controller: _otpController,
            label: 'Verification Code',
            hintText: 'Enter 6-digit OTP code',
            keyboardType: TextInputType.number,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          AppButton(
            label: 'Verify Code',
            onPressed: _verifyOtp,
            icon: Icons.check_circle_outline_rounded,
          ),
        ],
      ),
    );
  }
}
