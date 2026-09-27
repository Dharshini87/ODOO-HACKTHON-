import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_text_styles.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/system_feedback.dart';
import 'auth_provider.dart';

/// Step 2 of password-reset flow.
/// Shows 6 OTP digit boxes, a 60-second resend countdown, and a "Resend OTP" button.
/// On verify → navigate to /reset-password?email=&otp=
class OtpVerificationScreen extends ConsumerStatefulWidget {
  final String email;

  const OtpVerificationScreen({super.key, required this.email});

  @override
  ConsumerState<OtpVerificationScreen> createState() => _OtpVerificationScreenState();
}

class _OtpVerificationScreenState extends ConsumerState<OtpVerificationScreen> {
  final _otpController = TextEditingController();

  // Six individual controllers for visual OTP boxes
  final List<TextEditingController> _digitControllers =
      List.generate(6, (_) => TextEditingController());
  final List<FocusNode> _focusNodes = List.generate(6, (_) => FocusNode());

  Timer? _cooldownTimer;
  int _secondsRemaining = 0; // 0 = can resend

  @override
  void dispose() {
    _otpController.dispose();
    for (final c in _digitControllers) {
      c.dispose();
    }
    for (final f in _focusNodes) {
      f.dispose();
    }
    _cooldownTimer?.cancel();
    super.dispose();
  }

  String get _currentOtp =>
      _digitControllers.map((c) => c.text).join();

  bool get _canResend => _secondsRemaining <= 0;

  void _startCooldown([int seconds = 60]) {
    _cooldownTimer?.cancel();
    setState(() => _secondsRemaining = seconds);
    _cooldownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      setState(() {
        _secondsRemaining--;
        if (_secondsRemaining <= 0) {
          timer.cancel();
        }
      });
    });
  }

  void _onDigitChanged(int index, String value) {
    if (value.length > 1) {
      // Paste scenario — distribute across boxes
      final digits = value.replaceAll(RegExp(r'\D'), '');
      for (int i = 0; i < 6 && i < digits.length; i++) {
        _digitControllers[i].text = digits[i];
      }
      _focusNodes[5].requestFocus();
      setState(() {});
      return;
    }

    if (value.isNotEmpty && index < 5) {
      _focusNodes[index + 1].requestFocus();
    }
    setState(() {});
  }

  void _onDigitBackspace(int index) {
    if (_digitControllers[index].text.isEmpty && index > 0) {
      _digitControllers[index - 1].clear();
      _focusNodes[index - 1].requestFocus();
    }
  }

  Future<void> _handleResend() async {
    if (!_canResend) return;
    final authNotifier = ref.read(authProvider.notifier);
    await authNotifier.forgotPassword(widget.email);
    if (!mounted) return;
    final authState = ref.read(authProvider);
    if (authState.errorMessage != null) {
      // Rate-limited or other error
      AppFeedback.showError(context, authState.errorMessage!);
    } else {
      AppFeedback.showInfo(context, 'A new OTP has been sent to ${widget.email}');
      _startCooldown(60);
    }
  }

  void _handleVerify() {
    final otp = _currentOtp;
    if (otp.length < 6) {
      AppFeedback.showError(context, 'Please enter the complete 6-digit code');
      return;
    }

    // Navigate to reset-password screen — OTP verification happens at the reset step
    context.go(
      '/reset-password?email=${Uri.encodeComponent(widget.email)}&otp=${Uri.encodeComponent(otp)}',
    );
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authProvider);
    final enteredDigits = _currentOtp.length;

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
                      onPressed: () => context.go('/forgot-password'),
                    ),
                  ),
                  Container(
                    width: 64,
                    height: 64,
                    decoration: BoxDecoration(
                      color: AppColors.brand,
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: const Icon(
                      Icons.mark_email_read_outlined,
                      color: Colors.white,
                      size: 32,
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    'Verify Your Email',
                    style: AppTextStyles.displayMedium.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'We sent a 6-digit code to',
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
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  const SizedBox(height: 12),

                  // ── 6-digit OTP boxes ─────────────────────────────────────
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: List.generate(6, (i) => _buildDigitBox(i)),
                  ),

                  // Alternatively keep a plain text field for accessibility
                  const SizedBox(height: 28),

                  // ── Verify button ─────────────────────────────────────────
                  AppButton(
                    label: 'Verify Code',
                    onPressed: enteredDigits == 6 ? _handleVerify : null,
                    isLoading: authState.isLoading,
                    icon: Icons.verified_user_outlined,
                  ),

                  const SizedBox(height: 24),

                  // ── Resend OTP row ────────────────────────────────────────
                  _buildResendRow(),

                  const SizedBox(height: 16),
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

  Widget _buildDigitBox(int index) {
    final filled = _digitControllers[index].text.isNotEmpty;
    return SizedBox(
      width: 46,
      height: 56,
      child: KeyboardListener(
        focusNode: FocusNode(),
        onKeyEvent: (event) {
          if (event is KeyDownEvent &&
              event.logicalKey == LogicalKeyboardKey.backspace) {
            _onDigitBackspace(index);
          }
        },
        child: TextFormField(
          controller: _digitControllers[index],
          focusNode: _focusNodes[index],
          keyboardType: TextInputType.number,
          textAlign: TextAlign.center,
          maxLength: 1,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          style: AppTextStyles.displayMedium.copyWith(
            color: AppColors.ink,
            fontSize: 22,
          ),
          decoration: InputDecoration(
            counterText: '',
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(
                color: filled ? AppColors.brand : AppColors.line,
                width: filled ? 2 : 1.5,
              ),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: AppColors.brand, width: 2.5),
            ),
            filled: true,
            fillColor: filled
                ? AppColors.brandSubtle
                : AppColors.canvas,
          ),
          onChanged: (value) => _onDigitChanged(index, value),
        ),
      ),
    );
  }

  Widget _buildResendRow() {
    if (!_canResend) {
      return Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.timer_outlined, size: 16, color: AppColors.inkSecondary),
          const SizedBox(width: 6),
          Text(
            'Resend in $_secondsRemaining s',
            style: AppTextStyles.bodyMedium.copyWith(color: AppColors.inkSecondary),
          ),
        ],
      );
    }

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          'Didn\'t receive the code? ',
          style: AppTextStyles.bodyMedium.copyWith(color: AppColors.inkSecondary),
        ),
        TextButton(
          onPressed: _handleResend,
          style: TextButton.styleFrom(
            padding: EdgeInsets.zero,
            minimumSize: Size.zero,
          ),
          child: Text(
            'Resend OTP',
            style: AppTextStyles.labelLarge.copyWith(
              color: AppColors.brand,
              decoration: TextDecoration.underline,
            ),
          ),
        ),
      ],
    );
  }
}
