import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_spacing.dart';
import '../../../app/theme/app_text_styles.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/system_feedback.dart';
import '../../../core/widgets/app_text_field.dart';
import '../../../shared/providers/inventory_providers.dart';
import '../../auth/presentation/auth_provider.dart';

class ProductDetailScreen extends ConsumerStatefulWidget {
  final Map<String, dynamic> product;

  const ProductDetailScreen({super.key, required this.product});

  @override
  ConsumerState<ProductDetailScreen> createState() => _ProductDetailScreenState();
}

class _ProductDetailScreenState extends ConsumerState<ProductDetailScreen> {
  late Map<String, dynamic> _product;

  @override
  void initState() {
    super.initState();
    _product = Map<String, dynamic>.from(widget.product);
  }

  void _showEditProductDialog() {
    final nameCtrl = TextEditingController(text: _product['name'] as String? ?? '');
    final skuCtrl = TextEditingController(text: _product['sku'] as String? ?? '');
    final costVal = ((_product['unit_cost'] ?? _product['cost_per_unit']) as num?)?.toDouble() ?? 0.0;
    final costCtrl = TextEditingController(text: costVal.toStringAsFixed(2));
    final reorderVal = ((_product['reorder_level'] ?? _product['reorder_point']) as num?)?.toDouble() ?? 0.0;
    final reorderCtrl = TextEditingController(text: reorderVal.toInt().toString());
    String selectedUom = _product['unit_of_measure'] as String? ?? 'unit';
    int? selectedCatId = _product['category_id'] as int?;
    bool isActive = (_product['is_active'] as bool?) ?? true;
    bool isSaving = false;

    final uomOptions = ['unit', 'kg', 'pcs', 'meter', 'liter', 'box'];
    if (!uomOptions.contains(selectedUom.toLowerCase())) {
      uomOptions.add(selectedUom.toLowerCase());
    }

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.brand.withValues(alpha: 0.12),
                  borderRadius: AppSpacing.borderRadiusSm,
                ),
                child: const Icon(Icons.edit_note_rounded, color: AppColors.brand, size: 22),
              ),
              const SizedBox(width: 10),
              Text('Edit Product', style: AppTextStyles.headlineMedium),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AppTextField(
                  controller: nameCtrl,
                  label: 'Product Name',
                  hintText: 'Master catalog name',
                ),
                const SizedBox(height: AppSpacing.md),
                AppTextField(
                  controller: skuCtrl,
                  label: 'SKU / Barcode Code',
                  hintText: 'Unique product code',
                ),
                const SizedBox(height: AppSpacing.md),
                const SizedBox(height: AppSpacing.md),
                ref.watch(categoriesFutureProvider).when(
                  data: (cats) {
                    final activeCats = cats.where((c) => (c['is_active'] as bool?) ?? true).toList();
                    return DropdownButtonFormField<int>(
                      initialValue: selectedCatId,
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
                      onChanged: (val) => setDialogState(() => selectedCatId = val),
                    );
                  },
                  loading: () => const LinearProgressIndicator(),
                  error: (err, st) => const SizedBox.shrink(),
                ),
                const SizedBox(height: AppSpacing.md),
                DropdownButtonFormField<String>(
                  initialValue: selectedUom.toLowerCase(),
                  decoration: const InputDecoration(labelText: 'Unit of Measure'),
                  items: uomOptions.map((opt) {
                    return DropdownMenuItem(value: opt, child: Text(opt.toUpperCase()));
                  }).toList(),
                  onChanged: (val) {
                    if (val != null) setDialogState(() => selectedUom = val);
                  },
                ),
                const SizedBox(height: AppSpacing.md),
                AppTextField(
                  controller: costCtrl,
                  label: 'Cost Per Unit (₹)',
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                ),
                const SizedBox(height: AppSpacing.md),
                AppTextField(
                  controller: reorderCtrl,
                  label: 'Reorder Point Alert',
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                ),
                const SizedBox(height: AppSpacing.md),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text('Catalog Active', style: AppTextStyles.labelLarge),
                  subtitle: Text('Inactive products are hidden from standard operations', style: AppTextStyles.bodySmall),
                  value: isActive,
                  activeTrackColor: AppColors.brand,
                  onChanged: (v) => setDialogState(() => isActive = v),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: isSaving ? null : () => Navigator.pop(dialogCtx),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.brand,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              onPressed: isSaving
                  ? null
                  : () async {
                      final name = nameCtrl.text.trim();
                      final sku = skuCtrl.text.trim().toUpperCase();
                      if (name.isEmpty || sku.isEmpty) {
                        AppFeedback.showError(ctx, 'Product name and SKU are required');
                        return;
                      }

                      final cost = double.tryParse(costCtrl.text.trim()) ?? 0.0;
                      final reorder = double.tryParse(reorderCtrl.text.trim()) ?? 0.0;

                      setDialogState(() => isSaving = true);
                      try {
                        final repo = ref.read(masterDataRepositoryProvider);
                        final prodId = _product['id'] as int;
                        final updated = await repo.updateProduct(prodId, {
                          'name': name,
                          'sku': sku,
                          'category_id': selectedCatId,
                          'unit_of_measure': selectedUom,
                          'cost_per_unit': cost,
                          'reorder_point': reorder,
                          'reorder_level': reorder,
                          'is_active': isActive,
                        });

                        ref.invalidate(productsFutureProvider);
                        ref.invalidate(stockFutureProvider);
                        ref.invalidate(dashboardFutureProvider);

                        if (!mounted) return;
                        setState(() {
                          _product = Map<String, dynamic>.from(updated as Map<String, dynamic>);
                        });
                        if (dialogCtx.mounted) {
                          Navigator.pop(dialogCtx);
                        }
                        AppFeedback.showSuccess(context, 'Product "$name" updated successfully');
                      } catch (e) {
                        setDialogState(() => isSaving = false);
                        if (mounted) {
                          AppFeedback.showError(context, 'Failed to update product: $e');
                        }
                      }
                    },
              child: isSaving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Text('Save Changes'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authProvider).user;
    final isManager = user?.isManager ?? false;

    final name = _product['name'] as String? ?? 'Product';
    final sku = _product['sku'] as String? ?? '';
    final uom = _product['unit_of_measure'] as String? ?? 'unit';
    final cost = ((_product['unit_cost'] ?? _product['cost_per_unit']) as num?)?.toDouble() ?? 0.0;
    final reorder = ((_product['reorder_level'] ?? _product['reorder_point']) as num?)?.toDouble() ?? 0.0;
    final isActive = (_product['is_active'] as bool?) ?? true;

    return Scaffold(
      backgroundColor: AppColors.canvas,
      appBar: AppBar(
        title: Text(name, style: AppTextStyles.headlineLarge),
        actions: [
          // Edit Product is strictly for Inventory Managers
          if (isManager)
            IconButton(
              icon: const Icon(Icons.edit_outlined),
              tooltip: 'Edit Product',
              onPressed: _showEditProductDialog,
            ),
        ],
      ),
      body: ListView(
        padding: AppSpacing.pagePadding,
        children: [
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 56,
                      height: 56,
                      decoration: BoxDecoration(
                        color: AppColors.brand.withValues(alpha: 0.12),
                        borderRadius: AppSpacing.borderRadiusMd,
                      ),
                      child: const Icon(Icons.inventory_2_outlined, color: AppColors.brand, size: 30),
                    ),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(name, style: AppTextStyles.headlineMedium),
                          const SizedBox(height: 2),
                          Text('SKU: $sku', style: AppTextStyles.monoCode),
                        ],
                      ),
                    ),
                  ],
                ),
                const Divider(height: 24),
                if (_product['category_name'] != null || _product['category'] != null) ...[
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Category', style: AppTextStyles.bodySmall),
                      Text(
                        _product['category_name'] ?? _product['category']?['name'] ?? '',
                        style: AppTextStyles.labelLarge.copyWith(color: AppColors.brand),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                ],
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Unit of Measure', style: AppTextStyles.bodySmall),
                    Text(uom.toUpperCase(), style: AppTextStyles.labelLarge),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Cost per Unit', style: AppTextStyles.bodySmall),
                    Text('₹${cost.toStringAsFixed(2)}', style: AppTextStyles.labelLarge),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Reorder Point Threshold', style: AppTextStyles.bodySmall),
                    Text('${reorder.toInt()} $uom', style: AppTextStyles.labelLarge.copyWith(color: AppColors.amber)),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Catalog Status', style: AppTextStyles.bodySmall),
                    Text(
                      isActive ? 'ACTIVE' : 'INACTIVE',
                      style: AppTextStyles.labelSmall.copyWith(
                        color: isActive ? AppColors.statusDone : AppColors.statusCancelled,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                if (isManager) ...[
                  const Divider(height: 24),
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.brand,
                      side: const BorderSide(color: AppColors.brand),
                      minimumSize: const Size(double.infinity, 44),
                      shape: RoundedRectangleBorder(borderRadius: AppSpacing.borderRadiusMd),
                    ),
                    icon: const Icon(Icons.edit_note_rounded, size: 18),
                    label: const Text('Edit Product Specifications'),
                    onPressed: _showEditProductDialog,
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
