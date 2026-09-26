import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_spacing.dart';
import '../../../app/theme/app_text_styles.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/status_badge.dart';
import '../../../core/widgets/loading_view.dart';
import '../../../core/widgets/empty_view.dart';
import '../../../shared/providers/inventory_providers.dart';
import '../../stock/presentation/stock_detail_screen.dart';
import '../../deliveries/presentation/delivery_detail_screen.dart';

class GlobalSearchScreen extends ConsumerStatefulWidget {
  const GlobalSearchScreen({super.key});

  @override
  ConsumerState<GlobalSearchScreen> createState() => _GlobalSearchScreenState();
}

class _GlobalSearchScreenState extends ConsumerState<GlobalSearchScreen> {
  final _searchController = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final stockAsync = ref.watch(stockFutureProvider);
    final historyAsync = ref.watch(moveHistoryFutureProvider);

    return Scaffold(
      backgroundColor: AppColors.canvas,
      appBar: AppBar(
        title: TextField(
          controller: _searchController,
          autofocus: true,
          onChanged: (v) => setState(() => _query = v.trim().toLowerCase()),
          style: const TextStyle(color: Colors.white, fontSize: 16),
          cursorColor: Colors.white,
          decoration: InputDecoration(
            hintText: 'Search products, SKU, references, contacts...',
            hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.6)),
            border: InputBorder.none,
            enabledBorder: InputBorder.none,
            focusedBorder: InputBorder.none,
            suffixIcon: _query.isNotEmpty
                ? IconButton(
                    icon: const Icon(Icons.clear_rounded, color: Colors.white, size: 20),
                    onPressed: () {
                      _searchController.clear();
                      setState(() => _query = '');
                    },
                  )
                : null,
          ),
        ),
      ),
      body: _query.isEmpty
          ? const EmptyView(
              icon: Icons.search_rounded,
              title: 'Global Search',
              subtitle: 'Search across products by Name/SKU and transactions by Reference/Contact',
            )
          : ListView(
              padding: AppSpacing.pagePadding,
              children: [
                // Products Search Section (Section 34: Name, SKU)
                Text('Products & Stock', style: AppTextStyles.labelLarge.copyWith(color: AppColors.inkSecondary)),
                const SizedBox(height: AppSpacing.sm),
                stockAsync.when(
                  loading: () => const LoadingView(message: 'Searching catalog...'),
                  error: (e, _) => Text('Error: $e', style: AppTextStyles.bodySmall),
                  data: (items) {
                    final matching = items.where((it) {
                      return it.productName.toLowerCase().contains(_query) ||
                          it.sku.toLowerCase().contains(_query);
                    }).toList();

                    if (matching.isEmpty) {
                      return const Padding(
                        padding: EdgeInsets.symmetric(vertical: 8.0),
                        child: Text('No products matching this query.', style: TextStyle(color: AppColors.inkTertiary)),
                      );
                    }

                    return Column(
                      children: matching.map((it) {
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 8.0),
                          child: AppCard(
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(builder: (_) => StockDetailScreen(item: it)),
                              );
                            },
                            child: Row(
                              children: [
                                Container(
                                  width: 40,
                                  height: 40,
                                  decoration: BoxDecoration(
                                    color: AppColors.brand.withValues(alpha: 0.1),
                                    borderRadius: AppSpacing.borderRadiusMd,
                                  ),
                                  child: const Icon(Icons.inventory_2_outlined, color: AppColors.brand, size: 20),
                                ),
                                const SizedBox(width: AppSpacing.md),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(it.productName, style: AppTextStyles.headlineMedium),
                                      Text('SKU: ${it.sku} • On Hand: ${it.onHand.toInt()} ${it.unitOfMeasure}', style: AppTextStyles.bodySmall),
                                    ],
                                  ),
                                ),
                                StatusBadge(status: it.status),
                              ],
                            ),
                          ),
                        );
                      }).toList(),
                    );
                  },
                ),
                const SizedBox(height: AppSpacing.lg),

                // Transactions Search Section (Section 34: Reference, Contact)
                Text('Transactions & Ledger', style: AppTextStyles.labelLarge.copyWith(color: AppColors.inkSecondary)),
                const SizedBox(height: AppSpacing.sm),
                historyAsync.when(
                  loading: () => const LoadingView(message: 'Searching ledger...'),
                  error: (e, _) => Text('Error: $e', style: AppTextStyles.bodySmall),
                  data: (moves) {
                    final matching = moves.where((m) {
                      return m.reference.toLowerCase().contains(_query) ||
                          (m.contact ?? '').toLowerCase().contains(_query) ||
                          m.productName.toLowerCase().contains(_query);
                    }).toList();

                    if (matching.isEmpty) {
                      return const Padding(
                        padding: EdgeInsets.symmetric(vertical: 8.0),
                        child: Text('No transactions matching this query.', style: TextStyle(color: AppColors.inkTertiary)),
                      );
                    }

                    return Column(
                      children: matching.map((m) {
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 8.0),
                          child: AppCard(
                            onTap: () {
                              if (m.moveType.toLowerCase() == 'delivery') {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(builder: (_) => DeliveryDetailScreen(initialDelivery: m)),
                                );
                              }
                            },
                            child: Row(
                              children: [
                                Container(
                                  width: 40,
                                  height: 40,
                                  decoration: BoxDecoration(
                                    color: AppColors.ink.withValues(alpha: 0.08),
                                    borderRadius: AppSpacing.borderRadiusMd,
                                  ),
                                  child: const Icon(Icons.receipt_long_rounded, color: AppColors.ink, size: 20),
                                ),
                                const SizedBox(width: AppSpacing.md),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(m.reference, style: AppTextStyles.monoCode.copyWith(fontWeight: FontWeight.bold)),
                                      Text('${m.productName} • ${m.contact ?? m.moveType.toUpperCase()}', style: AppTextStyles.bodySmall),
                                    ],
                                  ),
                                ),
                                StatusBadge(status: m.status),
                              ],
                            ),
                          ),
                        );
                      }).toList(),
                    );
                  },
                ),
              ],
            ),
    );
  }
}
