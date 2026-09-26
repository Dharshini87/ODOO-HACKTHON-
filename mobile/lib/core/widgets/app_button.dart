import 'package:flutter/material.dart';
import '../../app/theme/app_colors.dart';
import '../../app/theme/app_spacing.dart';
import '../../app/theme/app_text_styles.dart';

enum AppButtonVariant { primary, secondary, danger, outline, text }

class AppButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final AppButtonVariant variant;
  final bool isLoading;
  final IconData? icon;
  final double? width;

  const AppButton({
    super.key,
    required this.label,
    this.onPressed,
    this.variant = AppButtonVariant.primary,
    this.isLoading = false,
    this.icon,
    this.width,
  });

  @override
  Widget build(BuildContext context) {
    Color bg;
    Color fg;
    BorderSide border = BorderSide.none;

    switch (variant) {
      case AppButtonVariant.primary:
        bg = AppColors.brand;
        fg = Colors.white;
        break;
      case AppButtonVariant.secondary:
        bg = AppColors.charcoal;
        fg = Colors.white;
        break;
      case AppButtonVariant.danger:
        bg = AppColors.statusCancelled;
        fg = Colors.white;
        break;
      case AppButtonVariant.outline:
        bg = Colors.transparent;
        fg = AppColors.ink;
        border = const BorderSide(color: AppColors.line);
        break;
      case AppButtonVariant.text:
        bg = Colors.transparent;
        fg = AppColors.brand;
        break;
    }

    final child = isLoading
        ? SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(
              strokeWidth: 2.2,
              valueColor: AlwaysStoppedAnimation<Color>(fg),
            ),
          )
        : Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 18, color: fg),
                const SizedBox(width: AppSpacing.sm),
              ],
              Text(
                label,
                style: AppTextStyles.labelLarge.copyWith(color: fg),
              ),
            ],
          );

    return SizedBox(
      width: width,
      height: 48,
      child: Material(
        color: onPressed == null ? bg.withValues(alpha: 0.5) : bg,
        shape: RoundedRectangleBorder(
          borderRadius: AppSpacing.borderRadiusMd,
          side: border,
        ),
        child: InkWell(
          onTap: isLoading ? null : onPressed,
          borderRadius: AppSpacing.borderRadiusMd,
          child: Center(child: child),
        ),
      ),
    );
  }
}
