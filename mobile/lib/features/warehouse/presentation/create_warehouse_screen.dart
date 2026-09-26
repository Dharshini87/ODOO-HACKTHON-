import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_spacing.dart';
import '../../../app/theme/app_text_styles.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_text_field.dart';
import '../../../core/widgets/system_feedback.dart';
import '../../../core/network/api_endpoints.dart';
import '../../../core/providers/core_providers.dart';
import '../../../shared/providers/inventory_providers.dart';

class CreateWarehouseScreen extends ConsumerStatefulWidget {
  const CreateWarehouseScreen({super.key});

  @override
  ConsumerState<CreateWarehouseScreen> createState() => _CreateWarehouseScreenState();
}

class _CreateWarehouseScreenState extends ConsumerState<CreateWarehouseScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _codeController = TextEditingController();
  final _addressController = TextEditingController();
  bool _isLoading = false;

  @override
  void dispose() {
    _nameController.dispose();
    _codeController.dispose();
    _addressController.dispose();
    super.dispose();
  }

  void _handleSubmit() async {
    if (!_formKey.currentState!.validate()) return;

    final name = _nameController.text.trim();
    final code = _codeController.text.trim().toUpperCase();
    final address = _addressController.text.trim();

    setState(() => _isLoading = true);
    try {
      final client = ref.read(apiClientProvider);
      await client.post(
        ApiEndpoints.warehouses,
        data: {
          'name': name,
          'short_code': code,
          'address': address.isEmpty ? null : address,
        },
      );

      ref.invalidate(warehousesFutureProvider);

      if (mounted) {
        AppFeedback.showSuccess(context, 'Warehouse "$name" ($code) created successfully!');
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        AppFeedback.showError(context, 'Failed to create warehouse: $e');
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.canvas,
      appBar: AppBar(
        title: Text('Create Warehouse', style: AppTextStyles.headlineLarge),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: AppSpacing.pagePadding,
          children: [
            AppTextField(
              controller: _nameController,
              label: 'Warehouse Name',
              hintText: 'e.g., Central Distribution Center',
              validator: (v) => (v == null || v.trim().isEmpty) ? 'Warehouse name is required' : null,
            ),
            const SizedBox(height: AppSpacing.md),
            AppTextField(
              controller: _codeController,
              label: 'Short Code',
              hintText: 'e.g., WH-MAIN, CDC',
              validator: (v) => (v == null || v.trim().isEmpty) ? 'Short code is required' : null,
            ),
            const SizedBox(height: AppSpacing.md),
            AppTextField(
              controller: _addressController,
              label: 'Address / Location Details',
              hintText: 'e.g., Plot 42, Industrial Area, Sector 5',
              maxLines: 3,
            ),
            const SizedBox(height: AppSpacing.xl),
            AppButton(
              label: 'Save Warehouse',
              onPressed: _handleSubmit,
              isLoading: _isLoading,
              icon: Icons.check_circle_outline_rounded,
            ),
          ],
        ),
      ),
    );
  }
}
