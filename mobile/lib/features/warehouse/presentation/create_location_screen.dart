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

class CreateLocationScreen extends ConsumerStatefulWidget {
  final int? preselectedWarehouseId;

  const CreateLocationScreen({super.key, this.preselectedWarehouseId});

  @override
  ConsumerState<CreateLocationScreen> createState() => _CreateLocationScreenState();
}

class _CreateLocationScreenState extends ConsumerState<CreateLocationScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _codeController = TextEditingController();
  int? _selectedWarehouseId;
  bool _isVirtual = false;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _selectedWarehouseId = widget.preselectedWarehouseId;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _codeController.dispose();
    super.dispose();
  }

  void _handleSubmit() async {
    if (!_formKey.currentState!.validate()) return;

    final name = _nameController.text.trim();
    final code = _codeController.text.trim().toUpperCase();

    setState(() => _isLoading = true);
    try {
      final client = ref.read(apiClientProvider);
      await client.post(
        ApiEndpoints.locations,
        data: {
          'name': name,
          'short_code': code,
          'warehouse_id': _selectedWarehouseId,
          'is_virtual': _isVirtual,
        },
      );

      ref.invalidate(locationsFutureProvider);

      if (mounted) {
        AppFeedback.showSuccess(context, 'Location "$name" ($code) created successfully!');
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        AppFeedback.showError(context, 'Failed to create location: $e');
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final warehousesAsync = ref.watch(warehousesFutureProvider);

    return Scaffold(
      backgroundColor: AppColors.canvas,
      appBar: AppBar(
        title: Text('Create Location', style: AppTextStyles.headlineLarge),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: AppSpacing.pagePadding,
          children: [
            AppTextField(
              controller: _nameController,
              label: 'Location Name',
              hintText: 'e.g., Rack A, Bin 12, Production Floor',
              validator: (v) => (v == null || v.trim().isEmpty) ? 'Location name is required' : null,
            ),
            const SizedBox(height: AppSpacing.md),
            AppTextField(
              controller: _codeController,
              label: 'Short Code',
              hintText: 'e.g., RACK-A, BIN-12',
              validator: (v) => (v == null || v.trim().isEmpty) ? 'Short code is required' : null,
            ),
            const SizedBox(height: AppSpacing.md),
            warehousesAsync.when(
              loading: () => const LinearProgressIndicator(),
              error: (e, _) => const SizedBox(),
              data: (whList) {
                return DropdownButtonFormField<int>(
                  initialValue: _selectedWarehouseId,
                  decoration: const InputDecoration(labelText: 'Warehouse Facility'),
                  items: whList.map((wh) {
                    final w = wh as Map<String, dynamic>;
                    return DropdownMenuItem<int>(
                      value: w['id'] as int?,
                      child: Text(w['name'] as String? ?? 'Warehouse'),
                    );
                  }).toList(),
                  onChanged: (val) => setState(() => _selectedWarehouseId = val),
                );
              },
            ),
            const SizedBox(height: AppSpacing.md),
            SwitchListTile.adaptive(
              title: const Text('Virtual Location'),
              subtitle: const Text('Check for virtual zones (e.g. Inbound Vendor, Customer Scrap)'),
              value: _isVirtual,
              activeThumbColor: AppColors.brand,
              onChanged: (v) => setState(() => _isVirtual = v),
            ),
            const SizedBox(height: AppSpacing.xl),
            AppButton(
              label: 'Save Location',
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
