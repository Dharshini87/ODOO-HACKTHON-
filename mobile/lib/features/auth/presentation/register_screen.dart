import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_spacing.dart';
import '../../../app/theme/app_text_styles.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_text_field.dart';
import 'auth_provider.dart';

class RegisterScreen extends ConsumerStatefulWidget {
  const RegisterScreen({super.key});

  @override
  ConsumerState<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends ConsumerState<RegisterScreen> {
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  String _selectedRole = 'WAREHOUSE_STAFF';
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  void _handleRegister() async {
    final name = _nameController.text.trim();
    final email = _emailController.text.trim();
    final password = _passwordController.text;
    final confirmPassword = _confirmPasswordController.text;

    if (name.isEmpty || email.isEmpty || password.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please fill in all required fields')),
      );
      return;
    }

    if (password != confirmPassword) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Passwords do not match')),
      );
      return;
    }

    final success = await ref.read(authProvider.notifier).register(
          name: name,
          email: email,
          password: password,
          role: _selectedRole,
        );

    if (success && mounted) {
      context.go('/home');
    } else if (mounted) {
      final error = ref.read(authProvider).errorMessage ?? 'Registration failed';
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
            // Dark Navy Hero Header matching UI/9.png
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
                  Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      color: AppColors.brand,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: const Icon(
                      Icons.person_add_rounded,
                      color: Colors.white,
                      size: 30,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Create Account',
                    style: AppTextStyles.displayMedium.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Join StockSense Inventory Management',
                    style: AppTextStyles.bodyMedium.copyWith(
                      color: AppColors.inkTertiary,
                    ),
                  ),
                ],
              ),
            ),

            // Registration Form
            Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  AppTextField(
                    label: 'Full Name',
                    hintText: 'John Doe',
                    controller: _nameController,
                    prefixIcon: const Icon(Icons.person_outline_rounded, size: 20, color: AppColors.inkSecondary),
                  ),
                  const SizedBox(height: 16),
                  AppTextField(
                    label: 'Email Address',
                    hintText: 'user@stocksense.com',
                    controller: _emailController,
                    keyboardType: TextInputType.emailAddress,
                    prefixIcon: const Icon(Icons.mail_outline_rounded, size: 20, color: AppColors.inkSecondary),
                  ),
                  const SizedBox(height: 16),

                  // Role Selector (Section 6: WAREHOUSE_STAFF vs INVENTORY_MANAGER)
                  Text('Assigned Role', style: AppTextStyles.labelLarge),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: GestureDetector(
                          onTap: () => setState(() => _selectedRole = 'WAREHOUSE_STAFF'),
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            decoration: BoxDecoration(
                              color: _selectedRole == 'WAREHOUSE_STAFF'
                                  ? AppColors.brand.withValues(alpha: 0.12)
                                  : AppColors.panel,
                              border: Border.all(
                                color: _selectedRole == 'WAREHOUSE_STAFF'
                                    ? AppColors.brand
                                    : AppColors.line,
                                width: _selectedRole == 'WAREHOUSE_STAFF' ? 1.5 : 1.0,
                              ),
                              borderRadius: AppSpacing.borderRadiusMd,
                            ),
                            child: Column(
                              children: [
                                Icon(
                                  Icons.badge_outlined,
                                  color: _selectedRole == 'WAREHOUSE_STAFF'
                                      ? AppColors.brand
                                      : AppColors.inkSecondary,
                                  size: 20,
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'Warehouse Staff',
                                  style: AppTextStyles.labelSmall.copyWith(
                                    color: _selectedRole == 'WAREHOUSE_STAFF'
                                        ? AppColors.brand
                                        : AppColors.ink,
                                    fontWeight: _selectedRole == 'WAREHOUSE_STAFF'
                                        ? FontWeight.w600
                                        : FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: GestureDetector(
                          onTap: () => setState(() => _selectedRole = 'INVENTORY_MANAGER'),
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            decoration: BoxDecoration(
                              color: _selectedRole == 'INVENTORY_MANAGER'
                                  ? AppColors.brand.withValues(alpha: 0.12)
                                  : AppColors.panel,
                              border: Border.all(
                                color: _selectedRole == 'INVENTORY_MANAGER'
                                    ? AppColors.brand
                                    : AppColors.line,
                                width: _selectedRole == 'INVENTORY_MANAGER' ? 1.5 : 1.0,
                              ),
                              borderRadius: AppSpacing.borderRadiusMd,
                            ),
                            child: Column(
                              children: [
                                Icon(
                                  Icons.admin_panel_settings_outlined,
                                  color: _selectedRole == 'INVENTORY_MANAGER'
                                      ? AppColors.brand
                                      : AppColors.inkSecondary,
                                  size: 20,
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'Inventory Manager',
                                  style: AppTextStyles.labelSmall.copyWith(
                                    color: _selectedRole == 'INVENTORY_MANAGER'
                                        ? AppColors.brand
                                        : AppColors.ink,
                                    fontWeight: _selectedRole == 'INVENTORY_MANAGER'
                                        ? FontWeight.w600
                                        : FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  AppTextField(
                    label: 'Password',
                    hintText: '••••••••',
                    controller: _passwordController,
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
                    label: 'Confirm Password',
                    hintText: '••••••••',
                    controller: _confirmPasswordController,
                    obscureText: _obscureConfirmPassword,
                    prefixIcon: const Icon(Icons.lock_outline_rounded, size: 20, color: AppColors.inkSecondary),
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscureConfirmPassword ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                        size: 20,
                        color: AppColors.inkSecondary,
                      ),
                      onPressed: () => setState(() => _obscureConfirmPassword = !_obscureConfirmPassword),
                    ),
                  ),
                  const SizedBox(height: 28),

                  AppButton(
                    label: 'Create Account',
                    onPressed: _handleRegister,
                    isLoading: authState.isLoading,
                  ),
                  const SizedBox(height: 20),

                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        'Already have an account? ',
                        style: AppTextStyles.bodyMedium.copyWith(color: AppColors.inkSecondary),
                      ),
                      GestureDetector(
                        onTap: () => context.go('/login'),
                        child: Text(
                          'Sign In',
                          style: AppTextStyles.labelLarge.copyWith(
                            color: AppColors.brand,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
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
