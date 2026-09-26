import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_spacing.dart';
import '../../../app/theme/app_text_styles.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_card.dart';
import '../../../shared/providers/inventory_providers.dart';

class CreateDeliveryScreen extends ConsumerStatefulWidget {
  const CreateDeliveryScreen({super.key});

  @override
  ConsumerState<CreateDeliveryScreen> createState() => _CreateDeliveryScreenState();
}

class _CreateDeliveryScreenState extends ConsumerState<CreateDeliveryScreen> {
  final _formKey = GlobalKey<FormState>();
  final _customerController = TextEditingController();
  final _quantityController = TextEditingController(text: '1');

  StockItem? _selectedStockItem;
  bool _isLoading = false;

  @override
  void dispose() {
    _customerController.dispose();
    _quantityController.dispose();
    super.dispose();
  }

  void _handleSubmit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedStockItem == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a product from stock')),
      );
      return;
    }

    final qty = double.tryParse(_quantityController.text.trim()) ?? 0.0;
    if (qty <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a valid positive quantity')),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final repo = ref.read(deliveriesRepositoryProvider);
      final payload = {
        'from_location_id': 1, // Default or selected warehouse location
        'product_id': _selectedStockItem!.productId,
        'quantity': qty,
        'contact': _customerController.text.trim().isEmpty ? 'Customer' : _customerController.text.trim(),
      };

      final created = await repo.createDelivery(payload);

      // Invalidate relevant providers to reload
      ref.invalidate(deliveriesFutureProvider);
      ref.invalidate(stockFutureProvider);
      ref.invalidate(dashboardFutureProvider);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Delivery ${created.reference} created (${created.status.toUpperCase()})'),
            backgroundColor: AppColors.brand,
          ),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to create delivery: $e'),
            backgroundColor: AppColors.statusCancelled,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final stockAsync = ref.watch(stockFutureProvider);
    final reqQty = double.tryParse(_quantityController.text.trim()) ?? 0.0;
    final isShortage = _selectedStockItem != null && reqQty > _selectedStockItem!.freeToUse;

    return Scaffold(
      backgroundColor: AppColors.canvas,
      appBar: AppBar(
        title: Text('Create Outbound Delivery', style: AppTextStyles.headlineLarge),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: AppSpacing.pagePadding,
          children: [
            Text('CUSTOMER / DESTINATION', style: AppTextStyles.labelSmall),
            const SizedBox(height: 6),
            TextFormField(
              controller: _customerController,
              decoration: const InputDecoration(
                hintText: 'e.g. Acme Corp / Customer Name',
                prefixIcon: Icon(Icons.person_outline_rounded),
              ),
              validator: (v) => (v == null || v.trim().isEmpty) ? 'Please enter customer or contact name' : null,
            ),
            const SizedBox(height: AppSpacing.md),

            Text('SELECT PRODUCT', style: AppTextStyles.labelSmall),
            const SizedBox(height: 6),
            stockAsync.when(
              loading: () => const LinearProgressIndicator(),
              error: (err, _) => Text('Error loading products: $err', style: AppTextStyles.bodySmall),
              data: (stockList) {
                if (stockList.isEmpty) {
                  return const Text('No products available in stock catalog.');
                }
                return DropdownButtonFormField<StockItem>(
                  initialValue: _selectedStockItem,
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.inventory_2_outlined),
                    hintText: 'Select item to dispatch',
                  ),
                  items: stockList.map((st) {
                    return DropdownMenuItem<StockItem>(
                      value: st,
                      child: Text(
                        '${st.productName} (${st.sku})',
                        style: AppTextStyles.bodyMedium,
                        overflow: TextOverflow.ellipsis,
                      ),
                    );
                  }).toList(),
                  onChanged: (val) {
                    setState(() {
                      _selectedStockItem = val;
                    });
                  },
                  validator: (v) => v == null ? 'Please choose a product' : null,
                );
              },
            ),

            if (_selectedStockItem != null) ...[
              const SizedBox(height: AppSpacing.md),
              AppCard(
                color: AppColors.panel,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('CURRENT STOCK STATUS', style: AppTextStyles.labelSmall),
                        Text('SKU: ${_selectedStockItem!.sku}', style: AppTextStyles.monoCode),
                      ],
                    ),
                    const Divider(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        Column(
                          children: [
                            Text('ON HAND', style: AppTextStyles.labelSmall),
                            const SizedBox(height: 2),
                            Text(
                              '${_selectedStockItem!.onHand.toInt()}',
                              style: AppTextStyles.headlineMedium.copyWith(color: AppColors.ink),
                            ),
                          ],
                        ),
                        Column(
                          children: [
                            Text('RESERVED', style: AppTextStyles.labelSmall),
                            const SizedBox(height: 2),
                            Text(
                              '${_selectedStockItem!.reserved.toInt()}',
                              style: AppTextStyles.headlineMedium.copyWith(color: AppColors.statusDraft),
                            ),
                          ],
                        ),
                        Column(
                          children: [
                            Text('FREE TO USE', style: AppTextStyles.labelSmall),
                            const SizedBox(height: 2),
                            Text(
                              '${_selectedStockItem!.freeToUse.toInt()}',
                              style: AppTextStyles.headlineMedium.copyWith(color: AppColors.statusDone),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],

            const SizedBox(height: AppSpacing.md),
            Text('REQUESTED QUANTITY', style: AppTextStyles.labelSmall),
            const SizedBox(height: 6),
            TextFormField(
              controller: _quantityController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.format_list_numbered_rounded),
                suffixText: 'units',
              ),
              onChanged: (_) => setState(() {}),
              validator: (v) {
                if (v == null || v.trim().isEmpty) return 'Enter quantity';
                final n = double.tryParse(v.trim());
                if (n == null || n <= 0) return 'Must be a positive number';
                return null;
              },
            ),

            if (isShortage) ...[
              const SizedBox(height: AppSpacing.sm),
              Container(
                padding: const EdgeInsets.all(AppSpacing.sm),
                decoration: BoxDecoration(
                  color: AppColors.statusDraft.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppColors.statusDraft),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.info_outline_rounded, color: AppColors.statusDraft, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Requested ($reqQty) exceeds Free to Use (${_selectedStockItem!.freeToUse.toInt()}). Delivery will be created in WAITING FOR STOCK status.',
                        style: AppTextStyles.bodySmall.copyWith(color: AppColors.statusDraft, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
              ),
            ],

            const SizedBox(height: AppSpacing.xl),
            AppButton(
              label: 'Create Delivery Order',
              onPressed: _handleSubmit,
              isLoading: _isLoading,
              icon: Icons.local_shipping_outlined,
            ),
          ],
        ),
      ),
    );
  }
}
