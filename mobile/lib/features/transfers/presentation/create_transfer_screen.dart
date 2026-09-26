import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_spacing.dart';
import '../../../app/theme/app_text_styles.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_card.dart';
import '../../../shared/providers/inventory_providers.dart';

class CreateTransferScreen extends ConsumerStatefulWidget {
  const CreateTransferScreen({super.key});

  @override
  ConsumerState<CreateTransferScreen> createState() => _CreateTransferScreenState();
}

class _CreateTransferScreenState extends ConsumerState<CreateTransferScreen> {
  final _formKey = GlobalKey<FormState>();
  final _quantityController = TextEditingController(text: '1');

  StockItem? _selectedStockItem;
  int _sourceLocationId = 1; // Default location 1
  int _destinationLocationId = 2; // Default location 2
  bool _isLoading = false;

  @override
  void dispose() {
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

    if (_sourceLocationId == _destinationLocationId) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Source and destination locations must differ.')),
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

    if (qty > _selectedStockItem!.freeToUse) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Cannot transfer more than FREE TO USE stock. Reserved stock cannot be transferred.'),
          backgroundColor: AppColors.statusCancelled,
        ),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final repo = ref.read(transfersRepositoryProvider);
      final payload = {
        'from_location_id': _sourceLocationId,
        'to_location_id': _destinationLocationId,
        'product_id': _selectedStockItem!.productId,
        'quantity': qty,
        'contact': 'Internal Location Move',
      };

      final created = await repo.createTransfer(payload);

      ref.invalidate(transfersFutureProvider);
      ref.invalidate(stockFutureProvider);
      ref.invalidate(dashboardFutureProvider);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Transfer ${created.reference} created (${created.status.toUpperCase()})'),
            backgroundColor: AppColors.brand,
          ),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Transfer creation failed: $e'),
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
    final isExceedsFree = _selectedStockItem != null && reqQty > _selectedStockItem!.freeToUse;

    return Scaffold(
      backgroundColor: AppColors.canvas,
      appBar: AppBar(
        title: Text('Create Internal Transfer', style: AppTextStyles.headlineLarge),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: AppSpacing.pagePadding,
          children: [
            // ROUTE CARD
            AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('INTERNAL ROUTE (LOCATIONS)', style: AppTextStyles.labelSmall),
                  const SizedBox(height: AppSpacing.sm),
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Source Location', style: AppTextStyles.bodySmall),
                            const SizedBox(height: 4),
                            DropdownButtonFormField<int>(
                              initialValue: _sourceLocationId,
                              decoration: const InputDecoration(isDense: true),
                              items: const [
                                DropdownMenuItem(value: 1, child: Text('Rack A (Warehouse)')),
                                DropdownMenuItem(value: 2, child: Text('Rack B (Warehouse)')),
                                DropdownMenuItem(value: 3, child: Text('Production Floor')),
                              ],
                              onChanged: (val) {
                                if (val != null) setState(() => _sourceLocationId = val);
                              },
                            ),
                          ],
                        ),
                      ),
                      const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 8),
                        child: Icon(Icons.arrow_forward_rounded, color: AppColors.brand),
                      ),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Destination Location', style: AppTextStyles.bodySmall),
                            const SizedBox(height: 4),
                            DropdownButtonFormField<int>(
                              initialValue: _destinationLocationId,
                              decoration: const InputDecoration(isDense: true),
                              items: const [
                                DropdownMenuItem(value: 1, child: Text('Rack A (Warehouse)')),
                                DropdownMenuItem(value: 2, child: Text('Rack B (Warehouse)')),
                                DropdownMenuItem(value: 3, child: Text('Production Floor')),
                              ],
                              onChanged: (val) {
                                if (val != null) setState(() => _destinationLocationId = val);
                              },
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  if (_sourceLocationId == _destinationLocationId) ...[
                    const SizedBox(height: 8),
                    Text(
                      'Source and destination locations must differ.',
                      style: AppTextStyles.bodySmall.copyWith(color: AppColors.statusCancelled),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.md),

            // PRODUCT SELECTION
            Text('SELECT PRODUCT TO TRANSFER', style: AppTextStyles.labelSmall),
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
                    hintText: 'Select item to move',
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
                        Text('SOURCE STOCK (SECTION 22)', style: AppTextStyles.labelSmall),
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
                    const SizedBox(height: 8),
                    Text(
                      'Rule: Transfer must use FREE TO USE stock only. Reserved inventory cannot be transferred.',
                      style: AppTextStyles.bodySmall.copyWith(color: AppColors.inkTertiary, fontStyle: FontStyle.italic),
                    ),
                  ],
                ),
              ),
            ],

            const SizedBox(height: AppSpacing.md),
            Text('TRANSFER QUANTITY', style: AppTextStyles.labelSmall),
            const SizedBox(height: 6),
            TextFormField(
              controller: _quantityController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.swap_horiz_rounded),
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

            if (isExceedsFree) ...[
              const SizedBox(height: AppSpacing.sm),
              Container(
                padding: const EdgeInsets.all(AppSpacing.sm),
                decoration: BoxDecoration(
                  color: AppColors.statusCancelled.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppColors.statusCancelled),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.error_outline_rounded, color: AppColors.statusCancelled, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Requested ($reqQty) exceeds Free to Use stock (${_selectedStockItem!.freeToUse.toInt()}). Reserved inventory cannot be transferred.',
                        style: AppTextStyles.bodySmall.copyWith(color: AppColors.statusCancelled, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
              ),
            ],

            const SizedBox(height: AppSpacing.xl),
            AppButton(
              label: 'Create Internal Transfer',
              onPressed: _handleSubmit,
              isLoading: _isLoading,
              icon: Icons.sync_alt_rounded,
            ),
          ],
        ),
      ),
    );
  }
}
