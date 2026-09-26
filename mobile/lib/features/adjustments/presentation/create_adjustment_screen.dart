import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_spacing.dart';
import '../../../app/theme/app_text_styles.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_card.dart';
import '../../../shared/providers/inventory_providers.dart';

class CreateAdjustmentScreen extends ConsumerStatefulWidget {
  const CreateAdjustmentScreen({super.key});

  @override
  ConsumerState<CreateAdjustmentScreen> createState() => _CreateAdjustmentScreenState();
}

class _CreateAdjustmentScreenState extends ConsumerState<CreateAdjustmentScreen> {
  final _formKey = GlobalKey<FormState>();
  final _physicalCountController = TextEditingController();

  StockItem? _selectedStockItem;
  int _locationId = 1; // Default location 1
  String _selectedReason = 'Counting Error';
  bool _isLoading = false;

  final List<String> _reasons = [
    'Damaged',
    'Lost',
    'Counting Error',
    'Found Stock',
    'Other',
  ];

  @override
  void dispose() {
    _physicalCountController.dispose();
    super.dispose();
  }

  void _handleSubmit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedStockItem == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a product')),
      );
      return;
    }

    final physical = double.tryParse(_physicalCountController.text.trim());
    if (physical == null || physical < 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a valid non-negative physical count')),
      );
      return;
    }

    // Section 23 Rule: Adjustment cannot result in on_hand < reserved
    if (physical < _selectedStockItem!.reserved) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Rule Violation: Physical count ($physical) cannot be less than reserved quantity (${_selectedStockItem!.reserved.toInt()}).'),
          backgroundColor: AppColors.statusCancelled,
        ),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final repo = ref.read(adjustmentsRepositoryProvider);
      final payload = {
        'location_id': _locationId,
        'product_id': _selectedStockItem!.productId,
        'physical_count': physical,
        'reason': _selectedReason,
      };

      final created = await repo.createAdjustment(payload);

      ref.invalidate(adjustmentsFutureProvider);
      ref.invalidate(stockFutureProvider);
      ref.invalidate(dashboardFutureProvider);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Adjustment ${created.reference} recorded in DRAFT. Pending Manager validation.'),
            backgroundColor: AppColors.brand,
          ),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Adjustment failed: $e'),
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
    final countVal = double.tryParse(_physicalCountController.text.trim());
    final systemQty = _selectedStockItem?.onHand ?? 0.0;
    final diff = countVal != null ? (countVal - systemQty) : 0.0;
    final isLessThenReserved = _selectedStockItem != null && countVal != null && countVal < _selectedStockItem!.reserved;

    return Scaffold(
      backgroundColor: AppColors.canvas,
      appBar: AppBar(
        title: Text('New Stock Count / Adjustment', style: AppTextStyles.headlineLarge),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: AppSpacing.pagePadding,
          children: [
            // LOCATION SELECTOR
            Text('LOCATION', style: AppTextStyles.labelSmall),
            const SizedBox(height: 6),
            DropdownButtonFormField<int>(
              initialValue: _locationId,
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.warehouse_outlined),
              ),
              items: const [
                DropdownMenuItem(value: 1, child: Text('Rack A (Main Warehouse)')),
                DropdownMenuItem(value: 2, child: Text('Rack B (Main Warehouse)')),
                DropdownMenuItem(value: 3, child: Text('Production Floor')),
              ],
              onChanged: (val) {
                if (val != null) setState(() => _locationId = val);
              },
            ),
            const SizedBox(height: AppSpacing.md),

            // PRODUCT SELECTION
            Text('PRODUCT', style: AppTextStyles.labelSmall),
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
                    hintText: 'Select item counted',
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
                      if (val != null) {
                        _physicalCountController.text = val.onHand.toInt().toString();
                      }
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
                        Text('CURRENT SYSTEM RECORDS', style: AppTextStyles.labelSmall),
                        Text('SKU: ${_selectedStockItem!.sku}', style: AppTextStyles.monoCode),
                      ],
                    ),
                    const Divider(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        Column(
                          children: [
                            Text('SYSTEM QUANTITY', style: AppTextStyles.labelSmall),
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
                              style: AppTextStyles.headlineMedium.copyWith(color: AppColors.brand),
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
            Text('PHYSICAL COUNT', style: AppTextStyles.labelSmall),
            const SizedBox(height: 6),
            TextFormField(
              controller: _physicalCountController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.calculate_outlined),
                suffixText: 'units',
                hintText: 'Enter counted physical units',
              ),
              onChanged: (_) => setState(() {}),
              validator: (v) {
                if (v == null || v.trim().isEmpty) return 'Enter physical count';
                final n = double.tryParse(v.trim());
                if (n == null || n < 0) return 'Must be a non-negative number';
                return null;
              },
            ),

            if (_selectedStockItem != null && countVal != null) ...[
              const SizedBox(height: AppSpacing.sm),
              Container(
                padding: const EdgeInsets.all(AppSpacing.sm),
                decoration: BoxDecoration(
                  color: isLessThenReserved
                      ? AppColors.statusCancelled.withValues(alpha: 0.12)
                      : (diff == 0 ? AppColors.canvas : AppColors.brand.withValues(alpha: 0.1)),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: isLessThenReserved ? AppColors.statusCancelled : (diff == 0 ? AppColors.line : AppColors.brand),
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('CALCULATED DIFFERENCE:', style: AppTextStyles.labelSmall),
                    Text(
                      '${diff > 0 ? '+' : ''}${diff.toInt()} units',
                      style: AppTextStyles.headlineSmall.copyWith(
                        color: diff > 0 ? AppColors.statusDone : (diff < 0 ? AppColors.statusCancelled : AppColors.ink),
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ],

            if (isLessThenReserved) ...[
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
                        'Section 23 Rule: Adjustment cannot result in on_hand < reserved (${_selectedStockItem!.reserved.toInt()} units reserved). Physical count is too low.',
                        style: AppTextStyles.bodySmall.copyWith(color: AppColors.statusCancelled, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
              ),
            ],

            const SizedBox(height: AppSpacing.md),
            Text('REASON (SECTION 23)', style: AppTextStyles.labelSmall),
            const SizedBox(height: 6),
            DropdownButtonFormField<String>(
              initialValue: _selectedReason,
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.help_outline_rounded),
              ),
              items: _reasons.map((r) {
                return DropdownMenuItem(value: r, child: Text(r));
              }).toList(),
              onChanged: (val) {
                if (val != null) setState(() => _selectedReason = val);
              },
            ),

            const SizedBox(height: AppSpacing.sm),
            Text(
              'Notice: Warehouse Staff can record counts in Draft. An Inventory Manager must validate them to apply ledger changes.',
              style: AppTextStyles.bodySmall.copyWith(color: AppColors.inkTertiary, fontStyle: FontStyle.italic),
            ),

            const SizedBox(height: AppSpacing.xl),
            AppButton(
              label: 'Submit Adjustment Count',
              onPressed: isLessThenReserved ? null : _handleSubmit,
              isLoading: _isLoading,
              icon: Icons.check_circle_outline_rounded,
            ),
          ],
        ),
      ),
    );
  }
}
