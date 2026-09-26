import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_spacing.dart';
import '../../../app/theme/app_text_styles.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_text_field.dart';
import '../../../shared/providers/inventory_providers.dart';

class CreateReceiptScreen extends ConsumerStatefulWidget {
  const CreateReceiptScreen({super.key});

  @override
  ConsumerState<CreateReceiptScreen> createState() => _CreateReceiptScreenState();
}

class _CreateReceiptScreenState extends ConsumerState<CreateReceiptScreen> {
  final _formKey = GlobalKey<FormState>();
  final _vendorController = TextEditingController();
  final _qtyController = TextEditingController();
  final _notesController = TextEditingController();

  int? _selectedProductId;
  int? _selectedLocationId;
  bool _isSubmitting = false;

  @override
  void dispose() {
    _vendorController.dispose();
    _qtyController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  void _handleSubmit() async {
    if (_selectedProductId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a product')),
      );
      return;
    }
    if (_selectedLocationId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a destination warehouse location')),
      );
      return;
    }
    final qty = double.tryParse(_qtyController.text.trim());
    if (qty == null || qty <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a valid incoming quantity (> 0)')),
      );
      return;
    }

    setState(() => _isSubmitting = true);
    try {
      final repo = ref.read(receiptsRepositoryProvider);
      final newReceipt = await repo.createReceipt({
        'product_id': _selectedProductId,
        'to_location_id': _selectedLocationId,
        'quantity': qty,
        'contact': _vendorController.text.trim().isEmpty ? 'Vendor' : _vendorController.text.trim(),
        'party_name': _vendorController.text.trim().isEmpty ? 'Vendor' : _vendorController.text.trim(),
      });

      ref.invalidate(receiptsFutureProvider);
      ref.invalidate(stockFutureProvider);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Receipt ${newReceipt.reference} created in DRAFT'),
            backgroundColor: AppColors.statusDraft,
          ),
        );
        context.pop();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to create receipt: $e'),
            backgroundColor: AppColors.statusCancelled,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final productsAsync = ref.watch(productsFutureProvider);
    final locationsAsync = ref.watch(locationsFutureProvider);

    return Scaffold(
      backgroundColor: AppColors.canvas,
      appBar: AppBar(
        title: Text('New Receipt', style: AppTextStyles.headlineLarge),
      ),
      body: SingleChildScrollView(
        padding: AppSpacing.pagePadding,
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Incoming Vendor Delivery', style: AppTextStyles.headlineSmall),
              const SizedBox(height: 4),
              Text(
                'Receive goods into warehouse inventory (Flow: DRAFT → READY → DONE)',
                style: AppTextStyles.bodySmall,
              ),
              const SizedBox(height: AppSpacing.lg),

              // Vendor / Supplier
              AppTextField(
                label: 'Vendor / Supplier',
                hintText: 'e.g. Apex Steel Supplies Ltd.',
                controller: _vendorController,
                prefixIcon: const Icon(Icons.business_rounded, size: 20, color: AppColors.inkSecondary),
              ),
              const SizedBox(height: AppSpacing.md),

              // Product Selector
              Text('Product', style: AppTextStyles.labelLarge),
              const SizedBox(height: 6),
              productsAsync.when(
                loading: () => const LinearProgressIndicator(),
                error: (e, _) => Text('Error loading products: $e', style: const TextStyle(color: Colors.red)),
                data: (products) {
                  return Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    decoration: BoxDecoration(
                      color: AppColors.panel,
                      borderRadius: AppSpacing.borderRadiusMd,
                      border: Border.all(color: AppColors.line),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<int>(
                        value: _selectedProductId,
                        isExpanded: true,
                        hint: Text('Select product to receive', style: AppTextStyles.bodyMedium),
                        items: products.map<DropdownMenuItem<int>>((p) {
                          final id = p['id'] as int;
                          final name = p['name'] as String? ?? 'Product';
                          final sku = p['sku'] as String? ?? '';
                          return DropdownMenuItem<int>(
                            value: id,
                            child: Text('$name ($sku)', style: AppTextStyles.bodyMedium),
                          );
                        }).toList(),
                        onChanged: (val) => setState(() => _selectedProductId = val),
                      ),
                    ),
                  );
                },
              ),
              const SizedBox(height: AppSpacing.md),

              // Destination Location
              Text('Destination Warehouse Location', style: AppTextStyles.labelLarge),
              const SizedBox(height: 6),
              locationsAsync.when(
                loading: () => const LinearProgressIndicator(),
                error: (e, _) => Text('Error loading locations: $e', style: const TextStyle(color: Colors.red)),
                data: (locations) {
                  return Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    decoration: BoxDecoration(
                      color: AppColors.panel,
                      borderRadius: AppSpacing.borderRadiusMd,
                      border: Border.all(color: AppColors.line),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<int>(
                        value: _selectedLocationId,
                        isExpanded: true,
                        hint: Text('Select destination location', style: AppTextStyles.bodyMedium),
                        items: locations.map<DropdownMenuItem<int>>((l) {
                          final id = l['id'] as int;
                          final name = l['name'] as String? ?? 'Location';
                          final code = l['short_code'] as String? ?? '';
                          return DropdownMenuItem<int>(
                            value: id,
                            child: Text('$name ($code)', style: AppTextStyles.bodyMedium),
                          );
                        }).toList(),
                        onChanged: (val) => setState(() => _selectedLocationId = val),
                      ),
                    ),
                  );
                },
              ),
              const SizedBox(height: AppSpacing.md),

              // Quantity
              AppTextField(
                label: 'Quantity Received',
                hintText: 'e.g. 100',
                controller: _qtyController,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                prefixIcon: const Icon(Icons.numbers_rounded, size: 20, color: AppColors.inkSecondary),
              ),
              const SizedBox(height: AppSpacing.md),

              // Notes
              AppTextField(
                label: 'Notes / PO Reference',
                hintText: 'e.g. Purchase Order #PO-8821',
                controller: _notesController,
                prefixIcon: const Icon(Icons.note_alt_outlined, size: 20, color: AppColors.inkSecondary),
              ),
              const SizedBox(height: AppSpacing.xl),

              // Submit Button
              AppButton(
                label: 'Create Draft Receipt',
                onPressed: _handleSubmit,
                isLoading: _isSubmitting,
                icon: Icons.check_circle_outline_rounded,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
