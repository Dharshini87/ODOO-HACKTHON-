import 'package:flutter/material.dart';
import '../../app/theme/app_colors.dart';
import '../../app/theme/app_spacing.dart';
import '../../app/theme/app_text_styles.dart';

enum AppButtonVariant { primary, navy, secondary, danger, outline, ghost, text }

class AppButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final AppButtonVariant variant;
  final bool isLoading;
  final IconData? icon;
  final double? width;
  final bool isCompact;

  const AppButton({
    super.key,
    required this.label,
    this.onPressed,
    this.variant = AppButtonVariant.primary,
    this.isLoading = false,
    this.icon,
    this.width,
    this.isCompact = false,
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
      case AppButtonVariant.navy:
        bg = AppColors.primaryNavy;
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
      case AppButtonVariant.ghost:
        bg = Colors.transparent;
        fg = AppColors.brand;
        border = const BorderSide(color: AppColors.brand, width: 1.2);
        break;
      case AppButtonVariant.text:
        bg = Colors.transparent;
        fg = AppColors.brand;
        break;
    }

    final visualHeight = isCompact ? 36.0 : 48.0;
    final textStyle = isCompact
        ? AppTextStyles.labelMedium.copyWith(color: fg, fontSize: 13)
        : AppTextStyles.labelLarge.copyWith(color: fg);
    final iconSize = isCompact ? 15.0 : 18.0;

    final child = isLoading
        ? SizedBox(
            width: isCompact ? 16 : 20,
            height: isCompact ? 16 : 20,
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
                Icon(icon, size: iconSize, color: fg),
                const SizedBox(width: AppSpacing.sm),
              ],
              Text(
                label,
                style: textStyle,
              ),
            ],
          );

    final visualButton = Material(
      color: onPressed == null ? bg.withValues(alpha: 0.5) : bg,
      shape: RoundedRectangleBorder(
        borderRadius: isCompact ? AppSpacing.borderRadiusSm : AppSpacing.borderRadiusMd,
        side: border,
      ),
      child: InkWell(
        onTap: isLoading ? null : onPressed,
        borderRadius: isCompact ? AppSpacing.borderRadiusSm : AppSpacing.borderRadiusMd,
        child: Container(
          width: width,
          height: visualHeight,
          padding: EdgeInsets.symmetric(horizontal: isCompact ? 12 : 16),
          alignment: Alignment.center,
          child: child,
        ),
      ),
    );

    if (isCompact) {
      // Accessible 48dp touch target around 36dp visual button
      return ConstrainedBox(
        constraints: BoxConstraints(
          minHeight: 48.0,
          minWidth: width ?? 48.0,
        ),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: isLoading ? null : onPressed,
          child: Center(
            child: visualButton,
          ),
        ),
      );
    }

    return SizedBox(
      width: width,
      height: 48.0,
      child: visualButton,
    );
  }
}
