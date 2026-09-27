import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_spacing.dart';
import '../../../app/theme/app_text_styles.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_text_field.dart';
import '../../../core/widgets/system_feedback.dart';
import '../../../core/widgets/access_denied_view.dart';
import '../../../core/network/api_endpoints.dart';
import '../../../core/providers/core_providers.dart';
import '../../../shared/providers/inventory_providers.dart';
import '../../auth/presentation/auth_provider.dart';

class CreateProductScreen extends ConsumerStatefulWidget {
  const CreateProductScreen({super.key});

  @override
  ConsumerState<CreateProductScreen> createState() => _CreateProductScreenState();
}

class _CreateProductScreenState extends ConsumerState<CreateProductScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _skuController = TextEditingController();
  final _costController = TextEditingController(text: '0.0');
  final _reorderController = TextEditingController(text: '10.0');
  String _uom = 'kg';
  int? _selectedCategoryId;
  bool _isLoading = false;

  final List<String> _uomOptions = ['kg', 'unit', 'pcs', 'meter', 'liter', 'box'];

  @override
  void dispose() {
    _nameController.dispose();
    _skuController.dispose();
    _costController.dispose();
    _reorderController.dispose();
    super.dispose();
  }

  void _handleSubmit() async {
    if (!_formKey.currentState!.validate()) return;

    final name = _nameController.text.trim();
    final sku = _skuController.text.trim().toUpperCase();
    final cost = double.tryParse(_costController.text.trim()) ?? 0.0;
    final reorder = double.tryParse(_reorderController.text.trim()) ?? 0.0;

    setState(() => _isLoading = true);
    try {
      final client = ref.read(apiClientProvider);
      await client.post(
        ApiEndpoints.products,
        data: {
          'name': name,
          'sku': sku,
          'category_id': _selectedCategoryId,
          'unit_of_measure': _uom,
          'cost_per_unit': cost,
          'reorder_point': reorder,
          'reorder_level': reorder,
        },
      );

      ref.invalidate(productsFutureProvider);
      ref.invalidate(stockFutureProvider);
      ref.invalidate(dashboardFutureProvider);

      if (mounted) {
        AppFeedback.showSuccess(context, 'Product "$name" ($sku) created successfully!');
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        AppFeedback.showError(context, 'Failed to create product: $e');
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authProvider).user;
    if (user != null && !user.isManager) {
      return const AccessRestrictedScaffold(
        title: 'Create Master Product',
        message: 'Only Inventory Managers have permission to create and manage catalog products.',
      );
    }

    return Scaffold(
      backgroundColor: AppColors.canvas,
      appBar: AppBar(
        title: Text('Create Master Product', style: AppTextStyles.headlineLarge),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: AppSpacing.pagePadding,
          children: [
            AppTextField(
              controller: _nameController,
              label: 'Product Name',
              hintText: 'e.g., Steel Rod, Hex Bolt, Copper Wire',
              validator: (v) => (v == null || v.trim().isEmpty) ? 'Product name is required' : null,
            ),
            const SizedBox(height: AppSpacing.md),
            AppTextField(
              controller: _skuController,
              label: 'SKU / Barcode Code',
              hintText: 'e.g., SR-001, HB-004',
              validator: (v) => (v == null || v.trim().isEmpty) ? 'SKU is required' : null,
            ),
            const SizedBox(height: AppSpacing.md),
            ref.watch(categoriesFutureProvider).when(
              data: (cats) {
                final activeCats = cats.where((c) => (c['is_active'] as bool?) ?? true).toList();
                return DropdownButtonFormField<int>(
                  initialValue: _selectedCategoryId,
                  decoration: const InputDecoration(labelText: 'Category (Optional)'),
                  items: [
                    const DropdownMenuItem<int>(
                      value: null,
                      child: Text('No Category'),
                    ),
                    ...activeCats.map((c) {
                      return DropdownMenuItem<int>(
                        value: c['id'] as int?,
                        child: Text(c['name']?.toString() ?? ''),
                      );
                    }),
                  ],
                  onChanged: (val) {
                    setState(() => _selectedCategoryId = val);
                  },
                );
              },
              loading: () => const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: LinearProgressIndicator(),
              ),
              error: (err, st) => const SizedBox.shrink(),
            ),
            const SizedBox(height: AppSpacing.md),
            DropdownButtonFormField<String>(
              initialValue: _uom,
              decoration: const InputDecoration(labelText: 'Unit of Measure'),
              items: _uomOptions.map((opt) {
                return DropdownMenuItem(value: opt, child: Text(opt.toUpperCase()));
              }).toList(),
              onChanged: (val) {
                if (val != null) setState(() => _uom = val);
              },
            ),
            const SizedBox(height: AppSpacing.md),
            AppTextField(
              controller: _costController,
              label: 'Cost Per Unit (₹)',
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              validator: (v) {
                final d = double.tryParse(v ?? '');
                if (d == null || d < 0) return 'Valid non-negative cost required';
                return null;
              },
            ),
            const SizedBox(height: AppSpacing.md),
            AppTextField(
              controller: _reorderController,
              label: 'Reorder Level (Alert Threshold)',
              hintText: 'Minimum inventory before alerting Low Stock',
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              validator: (v) {
                final d = double.tryParse(v ?? '');
                if (d == null || d < 0) return 'Reorder level must be >= 0';
                return null;
              },
            ),
            const SizedBox(height: AppSpacing.xl),
            AppButton(
              label: 'Save Product',
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
