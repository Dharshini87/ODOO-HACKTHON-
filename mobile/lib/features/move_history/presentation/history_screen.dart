import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_spacing.dart';
import '../../../app/theme/app_text_styles.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/status_badge.dart';
import '../../../core/widgets/loading_view.dart';
import '../../../core/widgets/error_view.dart';
import '../../../core/widgets/empty_view.dart';
import '../../../shared/providers/inventory_providers.dart';

class HistoryScreen extends ConsumerStatefulWidget {
  const HistoryScreen({super.key});

  @override
  ConsumerState<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends ConsumerState<HistoryScreen> with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  final _searchController = TextEditingController();

  // Section 25 Filters: Type, Status, Product, Warehouse, Location, Date
  String _selectedType = '';
  String _selectedStatus = '';
  String _selectedProduct = '';
  String _selectedWarehouse = '';
  String _selectedLocation = '';
  DateTime? _startDate;
  DateTime? _endDate;

  // Section 25 Search: Reference, Contact, SKU
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    // 3 tabs: Move History (List), Move History (Kanban), Stock Ledger (Timeline)
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  bool _hasActiveFilters() {
    return _selectedType.isNotEmpty ||
        _selectedStatus.isNotEmpty ||
        _selectedProduct.isNotEmpty ||
        _selectedWarehouse.isNotEmpty ||
        _selectedLocation.isNotEmpty ||
        _startDate != null ||
        _endDate != null;
  }

  void _clearAllFilters() {
    setState(() {
      _selectedType = '';
      _selectedStatus = '';
      _selectedProduct = '';
      _selectedWarehouse = '';
      _selectedLocation = '';
      _startDate = null;
      _endDate = null;
    });
  }

  String _formatDateTime(String? raw) {
    if (raw == null || raw.isEmpty) return 'Recent';
    final dt = DateTime.tryParse(raw);
    if (dt == null) return raw;
    final y = dt.year;
    final m = dt.month.toString().padLeft(2, '0');
    final d = dt.day.toString().padLeft(2, '0');
    final hr = dt.hour.toString().padLeft(2, '0');
    final min = dt.minute.toString().padLeft(2, '0');
    return '$y-$m-$d $hr:$min';
  }

  Color _getMovementTypeColor(String moveType) {
    switch (moveType.toUpperCase()) {
      case 'RECEIPT':
        return AppColors.statusDone; // Green
      case 'DELIVERY':
        return AppColors.statusCancelled; // Red
      case 'TRANSFER_IN':
        return const Color(0xFF0D9488); // Teal
      case 'TRANSFER_OUT':
        return const Color(0xFF6366F1); // Indigo
      case 'ADJUSTMENT':
        return AppColors.statusDraft; // Amber / Orange
      default:
        return AppColors.brand;
    }
  }

  IconData _getMovementTypeIcon(String moveType) {
    switch (moveType.toUpperCase()) {
      case 'RECEIPT':
        return Icons.call_received_rounded;
      case 'DELIVERY':
        return Icons.call_made_rounded;
      case 'TRANSFER_IN':
        return Icons.transit_enterexit_rounded;
      case 'TRANSFER_OUT':
        return Icons.logout_rounded;
      case 'ADJUSTMENT':
        return Icons.tune_rounded;
      default:
        return Icons.sync_alt_rounded;
    }
  }

  List<StockMoveItem> _applyMoveFilters(List<StockMoveItem> moves) {
    return moves.where((m) {
      if (_selectedType.isNotEmpty && m.moveType.toLowerCase() != _selectedType.toLowerCase()) {
        return false;
      }
      if (_selectedStatus.isNotEmpty && m.status.toLowerCase() != _selectedStatus.toLowerCase()) {
        return false;
      }
      if (_selectedProduct.isNotEmpty &&
          !m.productName.toLowerCase().contains(_selectedProduct.toLowerCase()) &&
          !m.sku.toLowerCase().contains(_selectedProduct.toLowerCase())) {
        return false;
      }
      if (_selectedWarehouse.isNotEmpty &&
          !m.fromLocationName.toLowerCase().contains(_selectedWarehouse.toLowerCase()) &&
          !m.toLocationName.toLowerCase().contains(_selectedWarehouse.toLowerCase())) {
        return false;
      }
      if (_selectedLocation.isNotEmpty &&
          !m.fromLocationName.toLowerCase().contains(_selectedLocation.toLowerCase()) &&
          !m.toLocationName.toLowerCase().contains(_selectedLocation.toLowerCase())) {
        return false;
      }
      if (_searchQuery.isNotEmpty) {
        // Section 25: Search Reference, Contact, SKU
        final refMatch = m.reference.toLowerCase().contains(_searchQuery);
        final contactMatch = (m.contact ?? '').toLowerCase().contains(_searchQuery);
        final skuMatch = m.sku.toLowerCase().contains(_searchQuery);
        final prodMatch = m.productName.toLowerCase().contains(_searchQuery);
        if (!refMatch && !contactMatch && !skuMatch && !prodMatch) return false;
      }
      if (_startDate != null) {
        final dateStr = m.date ?? m.createdAt;
        if (dateStr != null) {
          final dt = DateTime.tryParse(dateStr);
          if (dt != null && dt.isBefore(_startDate!)) return false;
        }
      }
      if (_endDate != null) {
        final dateStr = m.date ?? m.createdAt;
        if (dateStr != null) {
          final dt = DateTime.tryParse(dateStr);
          if (dt != null && dt.isAfter(_endDate!.add(const Duration(days: 1)))) return false;
        }
      }
      return true;
    }).toList();
  }

  List<StockLedgerItem> _applyLedgerFilters(List<StockLedgerItem> entries) {
    return entries.where((e) {
      if (_selectedType.isNotEmpty) {
        final clean = _selectedType.toLowerCase();
        final mv = e.movementType.toLowerCase();
        if (clean == 'receipt' && mv != 'receipt') return false;
        if (clean == 'delivery' && mv != 'delivery') return false;
        if (clean == 'transfer' && !mv.startsWith('transfer')) return false;
        if (clean == 'adjustment' && mv != 'adjustment') return false;
      }
      if (_selectedProduct.isNotEmpty &&
          !e.productName.toLowerCase().contains(_selectedProduct.toLowerCase()) &&
          !e.sku.toLowerCase().contains(_selectedProduct.toLowerCase())) {
        return false;
      }
      if (_selectedWarehouse.isNotEmpty &&
          (e.warehouseName == null || !e.warehouseName!.toLowerCase().contains(_selectedWarehouse.toLowerCase()))) {
        return false;
      }
      if (_selectedLocation.isNotEmpty &&
          !e.locationName.toLowerCase().contains(_selectedLocation.toLowerCase())) {
        return false;
      }
      if (_searchQuery.isNotEmpty) {
        final refMatch = (e.reference ?? '').toLowerCase().contains(_searchQuery);
        final skuMatch = e.sku.toLowerCase().contains(_searchQuery);
        final prodMatch = e.productName.toLowerCase().contains(_searchQuery);
        final locMatch = e.locationName.toLowerCase().contains(_searchQuery);
        if (!refMatch && !skuMatch && !prodMatch && !locMatch) return false;
      }
      if (_startDate != null) {
        final dt = DateTime.tryParse(e.createdAt);
        if (dt != null && dt.isBefore(_startDate!)) return false;
      }
      if (_endDate != null) {
        final dt = DateTime.tryParse(e.createdAt);
        if (dt != null && dt.isAfter(_endDate!.add(const Duration(days: 1)))) return false;
      }
      return true;
    }).toList();
  }

  void _showFilterSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.panel,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) {
          final stockItems = ref.watch(stockFutureProvider).asData?.value ?? [];
          final productNames = stockItems.map((s) => s.productName).toSet().toList();

          return Padding(
            padding: EdgeInsets.only(
              left: 20,
              right: 20,
              top: 20,
              bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Filter Moves & Ledger', style: AppTextStyles.headlineLarge),
                      TextButton(
                        onPressed: () {
                          _clearAllFilters();
                          setSheetState(() {});
                          Navigator.pop(ctx);
                        },
                        child: const Text('Reset All'),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    'Section 25: Filter by Type, Status, Product, Warehouse, Location, Date',
                    style: AppTextStyles.bodySmall.copyWith(color: AppColors.inkTertiary),
                  ),
                  const SizedBox(height: AppSpacing.md),

                  // 1. Transaction Type
                  Text('Transaction Type', style: AppTextStyles.labelLarge),
                  const SizedBox(height: AppSpacing.xs),
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: ['', 'receipt', 'delivery', 'transfer', 'adjustment'].map((type) {
                      final label = type.isEmpty ? 'All Types' : type.toUpperCase();
                      final isSelected = _selectedType == type;
                      return ChoiceChip(
                        label: Text(label),
                        selected: isSelected,
                        selectedColor: AppColors.brand.withValues(alpha: 0.15),
                        onSelected: (val) {
                          setSheetState(() => _selectedType = val ? type : '');
                          setState(() => _selectedType = val ? type : '');
                        },
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: AppSpacing.md),

                  // 2. Transaction Status
                  Text('Transaction Status', style: AppTextStyles.labelLarge),
                  const SizedBox(height: AppSpacing.xs),
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: ['', 'draft', 'waiting', 'ready', 'done', 'canceled'].map((status) {
                      final label = status.isEmpty ? 'All Statuses' : status.toUpperCase();
                      final isSelected = _selectedStatus == status;
                      return ChoiceChip(
                        label: Text(label),
                        selected: isSelected,
                        selectedColor: AppColors.brand.withValues(alpha: 0.15),
                        onSelected: (val) {
                          setSheetState(() => _selectedStatus = val ? status : '');
                          setState(() => _selectedStatus = val ? status : '');
                        },
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: AppSpacing.md),

                  // 3. Product Filter
                  Text('Product', style: AppTextStyles.labelLarge),
                  const SizedBox(height: AppSpacing.xs),
                  if (productNames.isNotEmpty)
                    DropdownButtonFormField<String>(
                      initialValue: _selectedProduct.isEmpty ? null : _selectedProduct,
                      decoration: const InputDecoration(
                        hintText: 'All Products',
                        contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      ),
                      items: [
                        const DropdownMenuItem(value: '', child: Text('All Products')),
                        ...productNames.map((p) => DropdownMenuItem(value: p, child: Text(p))),
                      ],
                      onChanged: (val) {
                        setSheetState(() => _selectedProduct = val ?? '');
                        setState(() => _selectedProduct = val ?? '');
                      },
                    )
                  else
                    TextField(
                      decoration: const InputDecoration(
                        hintText: 'Filter by Product Name or SKU',
                        contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      ),
                      onChanged: (val) {
                        setSheetState(() => _selectedProduct = val.trim());
                        setState(() => _selectedProduct = val.trim());
                      },
                    ),
                  const SizedBox(height: AppSpacing.md),

                  // 4. Warehouse & Location
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Warehouse', style: AppTextStyles.labelLarge),
                            const SizedBox(height: AppSpacing.xs),
                            TextField(
                              decoration: const InputDecoration(
                                hintText: 'e.g. Main',
                                contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                              ),
                              controller: TextEditingController(text: _selectedWarehouse),
                              onChanged: (val) {
                                _selectedWarehouse = val.trim();
                                setState(() {});
                              },
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Location', style: AppTextStyles.labelLarge),
                            const SizedBox(height: AppSpacing.xs),
                            TextField(
                              decoration: const InputDecoration(
                                hintText: 'e.g. Rack A',
                                contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                              ),
                              controller: TextEditingController(text: _selectedLocation),
                              onChanged: (val) {
                                _selectedLocation = val.trim();
                                setState(() {});
                              },
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.md),

                  // 5. Date Range
                  Text('Date Range', style: AppTextStyles.labelLarge),
                  const SizedBox(height: AppSpacing.xs),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          icon: const Icon(Icons.calendar_today_rounded, size: 16),
                          label: Text(_startDate == null
                              ? 'Start Date'
                              : '${_startDate!.year}-${_startDate!.month.toString().padLeft(2, '0')}-${_startDate!.day.toString().padLeft(2, '0')}'),
                          onPressed: () async {
                            final picked = await showDatePicker(
                              context: context,
                              initialDate: _startDate ?? DateTime.now(),
                              firstDate: DateTime(2020),
                              lastDate: DateTime(2030),
                            );
                            if (picked != null) {
                              setSheetState(() => _startDate = picked);
                              setState(() => _startDate = picked);
                            }
                          },
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton.icon(
                          icon: const Icon(Icons.calendar_today_rounded, size: 16),
                          label: Text(_endDate == null
                              ? 'End Date'
                              : '${_endDate!.year}-${_endDate!.month.toString().padLeft(2, '0')}-${_endDate!.day.toString().padLeft(2, '0')}'),
                          onPressed: () async {
                            final picked = await showDatePicker(
                              context: context,
                              initialDate: _endDate ?? DateTime.now(),
                              firstDate: DateTime(2020),
                              lastDate: DateTime(2030),
                            );
                            if (picked != null) {
                              setSheetState(() => _endDate = picked);
                              setState(() => _endDate = picked);
                            }
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  ElevatedButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text('Apply Filters'),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  // ============================================================
  // SECTION 25: MOVE HISTORY CARD (List View & Kanban)
  // Display: Reference, Date, Contact, From, To, Quantity, Status
  // ============================================================
  Widget _buildMoveCard(StockMoveItem m) {
    final isIncoming = m.moveType.toLowerCase() == 'receipt' ||
        (m.moveType.toLowerCase() == 'adjustment' && (m.difference ?? 0) >= 0);

    final fromDisplay = m.fromLocationName.isEmpty ? 'External Supplier' : m.fromLocationName;
    final toDisplay = m.toLocationName.isEmpty ? 'Customer Dispatched' : m.toLocationName;
    final contactDisplay = (m.contact != null && m.contact!.isNotEmpty)
        ? m.contact!
        : 'Internal / Direct';
    final dateDisplay = _formatDateTime(m.date ?? m.createdAt);

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header: Reference, Date, Status
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: _getMovementTypeColor(m.moveType).withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        m.moveType.toUpperCase(),
                        style: AppTextStyles.labelSmall.copyWith(
                          color: _getMovementTypeColor(m.moveType),
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        m.reference,
                        style: AppTextStyles.monoCode.copyWith(
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
              StatusBadge(status: m.status),
            ],
          ),
          const SizedBox(height: 6),

          // Date & Contact
          Row(
            children: [
              Expanded(
                child: Row(
                  children: [
                    const Icon(Icons.access_time_rounded, size: 13, color: AppColors.inkTertiary),
                    const SizedBox(width: 4),
                    Flexible(
                      child: Text(
                        dateDisplay,
                        style: AppTextStyles.bodySmall.copyWith(color: AppColors.inkTertiary, fontSize: 11),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    const Icon(Icons.person_outline_rounded, size: 13, color: AppColors.inkSecondary),
                    const SizedBox(width: 4),
                    Flexible(
                      child: Text(
                        contactDisplay,
                        style: AppTextStyles.bodySmall.copyWith(
                          color: AppColors.inkSecondary,
                          fontWeight: FontWeight.w600,
                          fontSize: 11,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),

          // Product & SKU
          Text(m.productName, style: AppTextStyles.headlineMedium),
          const SizedBox(height: 2),
          Text('SKU: ${m.sku}', style: AppTextStyles.bodySmall.copyWith(color: AppColors.inkTertiary)),
          const SizedBox(height: 6),

          // Route: From -> To
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: AppColors.canvas,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: AppColors.line),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('FROM', style: AppTextStyles.labelSmall.copyWith(fontSize: 10, color: AppColors.inkTertiary)),
                      Text(fromDisplay, style: AppTextStyles.bodySmall.copyWith(fontWeight: FontWeight.w600), maxLines: 1, overflow: TextOverflow.ellipsis),
                    ],
                  ),
                ),
                const Icon(Icons.arrow_forward_rounded, size: 16, color: AppColors.brand),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text('TO', style: AppTextStyles.labelSmall.copyWith(fontSize: 10, color: AppColors.inkTertiary)),
                      Text(toDisplay, style: AppTextStyles.bodySmall.copyWith(fontWeight: FontWeight.w600), maxLines: 1, overflow: TextOverflow.ellipsis),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 16),

          // Footer: Quantity
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Flexible(
                child: Text(
                  'DERIVED MOVE',
                  style: AppTextStyles.labelSmall.copyWith(
                    color: AppColors.inkTertiary,
                    letterSpacing: 0.5,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '${isIncoming ? '+' : '-'}${m.quantity.toInt()} kg',
                style: AppTextStyles.headlineSmall.copyWith(
                  color: isIncoming ? AppColors.statusDone : AppColors.statusCancelled,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ============================================================
  // SECTION 25: MOVE HISTORY KANBAN COLUMN
  // Support Kanban view as secondary/optional
  // ============================================================
  Widget _buildKanbanColumn(String title, String status, List<StockMoveItem> items) {
    final colItems = items.where((it) => it.status.toLowerCase() == status.toLowerCase()).toList();

    return Container(
      width: 290,
      margin: const EdgeInsets.only(right: 12),
      decoration: BoxDecoration(
        color: AppColors.panel,
        borderRadius: AppSpacing.borderRadiusMd,
        border: Border.all(color: AppColors.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    StatusBadge(status: status, fontSize: 10),
                    const SizedBox(width: 8),
                    Text(title, style: AppTextStyles.labelLarge),
                  ],
                ),
                CircleAvatar(
                  radius: 12,
                  backgroundColor: AppColors.canvas,
                  child: Text(
                    '${colItems.length}',
                    style: AppTextStyles.labelSmall.copyWith(fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: colItems.isEmpty
                ? Center(
                    child: Text(
                      'No $title moves',
                      style: AppTextStyles.bodySmall.copyWith(color: AppColors.inkTertiary),
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.all(8),
                    itemCount: colItems.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 8),
                    itemBuilder: (context, i) => _buildMoveCard(colItems[i]),
                  ),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // SECTION 24: STOCK LEDGER VERTICAL TIMELINE
  // Table: stock_ledger
  // - id, transaction_id, product_id, location_id,
  // - quantity_before, quantity_change, quantity_after,
  // - movement_type, created_at
  // Movement types: RECEIPT, DELIVERY, TRANSFER_IN, TRANSFER_OUT, ADJUSTMENT
  // Ledger is: READ ONLY, APPEND ONLY, IMMUTABLE
  // Mobile UI should display ledger as a vertical timeline.
  // ============================================================
  Widget _buildLedgerVerticalTimeline(List<StockLedgerItem> entries) {
    if (entries.isEmpty) {
      return const EmptyView(
        title: 'Empty Stock Ledger',
        subtitle: 'No immutable audit entries found matching your criteria.',
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      itemCount: entries.length,
      itemBuilder: (context, index) {
        final entry = entries[index];
        final isFirst = index == 0;
        final isLast = index == entries.length - 1;
        final typeColor = _getMovementTypeColor(entry.movementType);
        final typeIcon = _getMovementTypeIcon(entry.movementType);
        final isPositiveChange = entry.quantityChange >= 0;
        final dateFormatted = _formatDateTime(entry.createdAt);

        return IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 1. Vertical Timeline Indicator Column
              SizedBox(
                width: 44,
                child: Column(
                  children: [
                    // Top line
                    Container(
                      width: 2,
                      height: 16,
                      color: isFirst ? Colors.transparent : AppColors.line,
                    ),
                    // Timeline Node Circle
                    Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: typeColor.withValues(alpha: 0.15),
                        shape: BoxShape.circle,
                        border: Border.all(color: typeColor, width: 2),
                      ),
                      child: Icon(typeIcon, size: 16, color: typeColor),
                    ),
                    // Bottom connecting line
                    Expanded(
                      child: Container(
                        width: 2,
                        color: isLast ? Colors.transparent : AppColors.line,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),

              // 2. Vertical Timeline Node Content Card
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: AppCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Top Header: Movement Type, Reference, Immutable Tag
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: typeColor.withValues(alpha: 0.15),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    entry.movementType,
                                    style: AppTextStyles.labelSmall.copyWith(
                                      color: typeColor,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 6),
                                if (entry.reference != null && entry.reference!.isNotEmpty)
                                  Text(
                                    entry.reference!,
                                    style: AppTextStyles.monoCode.copyWith(
                                      fontWeight: FontWeight.w700,
                                      fontSize: 13,
                                    ),
                                  ),
                              ],
                            ),
                            // Immutable Ledger Badge
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: AppColors.canvas,
                                borderRadius: BorderRadius.circular(4),
                                border: Border.all(color: AppColors.line),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.lock_rounded, size: 10, color: AppColors.inkTertiary),
                                  const SizedBox(width: 3),
                                  Text(
                                    '#${entry.id}',
                                    style: AppTextStyles.labelSmall.copyWith(
                                      fontSize: 10,
                                      color: AppColors.inkTertiary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),

                        // Timestamp
                        Row(
                          children: [
                            const Icon(Icons.schedule_rounded, size: 13, color: AppColors.inkTertiary),
                            const SizedBox(width: 4),
                            Text(dateFormatted, style: AppTextStyles.bodySmall.copyWith(color: AppColors.inkTertiary)),
                          ],
                        ),
                        const SizedBox(height: 8),

                        // Product Name & SKU
                        Text(entry.productName, style: AppTextStyles.headlineMedium),
                        const SizedBox(height: 2),
                        Text(
                          'SKU: ${entry.sku}  •  ${entry.locationName}${entry.warehouseName != null ? ' (${entry.warehouseName})' : ''}',
                          style: AppTextStyles.bodySmall.copyWith(color: AppColors.inkSecondary),
                        ),
                        const SizedBox(height: 10),

                        // Section 24 Core: Arithmetic Delta Progression Box
                        // quantity_before -> quantity_change -> quantity_after
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          decoration: BoxDecoration(
                            color: AppColors.canvas,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: AppColors.line),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              // Quantity Before
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('BEFORE', style: AppTextStyles.labelSmall.copyWith(fontSize: 10, color: AppColors.inkTertiary)),
                                  const SizedBox(height: 2),
                                  Text(
                                    '${entry.quantityBefore.toStringAsFixed(1)} kg',
                                    style: AppTextStyles.bodySmall.copyWith(fontWeight: FontWeight.w600),
                                  ),
                                ],
                              ),
                              // Arrow
                              const Icon(Icons.arrow_forward_rounded, size: 14, color: AppColors.inkTertiary),
                              // Quantity Change
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.center,
                                children: [
                                  Text('CHANGE', style: AppTextStyles.labelSmall.copyWith(fontSize: 10, color: AppColors.inkTertiary)),
                                  const SizedBox(height: 2),
                                  Text(
                                    '${isPositiveChange ? '+' : ''}${entry.quantityChange.toStringAsFixed(1)} kg',
                                    style: AppTextStyles.labelLarge.copyWith(
                                      color: isPositiveChange ? AppColors.statusDone : AppColors.statusCancelled,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                              // Arrow
                              const Icon(Icons.arrow_forward_rounded, size: 14, color: AppColors.inkTertiary),
                              // Quantity After
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Text('AFTER', style: AppTextStyles.labelSmall.copyWith(fontSize: 10, color: AppColors.brand)),
                                  const SizedBox(height: 2),
                                  Text(
                                    '${entry.quantityAfter.toStringAsFixed(1)} kg',
                                    style: AppTextStyles.headlineSmall.copyWith(
                                      fontWeight: FontWeight.w700,
                                      color: AppColors.ink,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 8),

                        // Section 24 Invariance Guarantee
                        Text(
                          'READ ONLY • APPEND ONLY • IMMUTABLE AUDIT TRAIL',
                          style: AppTextStyles.labelSmall.copyWith(
                            fontSize: 9,
                            letterSpacing: 0.6,
                            color: AppColors.inkTertiary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // Active filters bar
  Widget _buildActiveFiltersBar() {
    if (!_hasActiveFilters()) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      color: AppColors.brand.withValues(alpha: 0.05),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            Text('Filters:', style: AppTextStyles.labelSmall.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(width: 8),
            if (_selectedType.isNotEmpty)
              _buildFilterChip('Type: ${_selectedType.toUpperCase()}', () => setState(() => _selectedType = '')),
            if (_selectedStatus.isNotEmpty)
              _buildFilterChip('Status: ${_selectedStatus.toUpperCase()}', () => setState(() => _selectedStatus = '')),
            if (_selectedProduct.isNotEmpty)
              _buildFilterChip('Product: $_selectedProduct', () => setState(() => _selectedProduct = '')),
            if (_selectedWarehouse.isNotEmpty)
              _buildFilterChip('WH: $_selectedWarehouse', () => setState(() => _selectedWarehouse = '')),
            if (_selectedLocation.isNotEmpty)
              _buildFilterChip('Loc: $_selectedLocation', () => setState(() => _selectedLocation = '')),
            if (_startDate != null)
              _buildFilterChip('From: ${_startDate!.year}-${_startDate!.month}-${_startDate!.day}', () => setState(() => _startDate = null)),
            if (_endDate != null)
              _buildFilterChip('To: ${_endDate!.year}-${_endDate!.month}-${_endDate!.day}', () => setState(() => _endDate = null)),
            TextButton(
              onPressed: _clearAllFilters,
              style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
              child: const Text('Clear All', style: TextStyle(fontSize: 12)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFilterChip(String label, VoidCallback onDeleted) {
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: Chip(
        label: Text(label, style: const TextStyle(fontSize: 11)),
        deleteIcon: const Icon(Icons.close_rounded, size: 14),
        onDeleted: onDeleted,
        visualDensity: VisualDensity.compact,
        backgroundColor: AppColors.panel,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final movesAsync = ref.watch(moveHistoryFutureProvider);
    final ledgerAsync = ref.watch(ledgerFutureProvider);

    return Scaffold(
      backgroundColor: AppColors.canvas,
      appBar: AppBar(
        title: Text('Move History & Ledger', style: AppTextStyles.headlineLarge),
        actions: [
          Stack(
            children: [
              IconButton(
                icon: const Icon(Icons.filter_list_rounded),
                tooltip: 'Filter Move History & Ledger',
                onPressed: _showFilterSheet,
              ),
              if (_hasActiveFilters())
                Positioned(
                  right: 8,
                  top: 8,
                  child: Container(
                    width: 9,
                    height: 9,
                    decoration: const BoxDecoration(
                      color: AppColors.brand,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
            ],
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          labelColor: AppColors.brand,
          unselectedLabelColor: AppColors.inkTertiary,
          indicatorColor: AppColors.brand,
          indicatorWeight: 3,
          labelStyle: AppTextStyles.labelLarge,
          tabs: const [
            Tab(icon: Icon(Icons.list_alt_rounded, size: 18), text: 'Moves (List)'),
            Tab(icon: Icon(Icons.view_kanban_outlined, size: 18), text: 'Moves (Kanban)'),
            Tab(icon: Icon(Icons.timeline_rounded, size: 18), text: 'Stock Ledger'),
          ],
        ),
      ),
      body: Column(
        children: [
          // Section 25: Search by Reference, Contact, SKU
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: TextField(
              controller: _searchController,
              onChanged: (v) => setState(() => _searchQuery = v.trim().toLowerCase()),
              decoration: InputDecoration(
                hintText: 'Search by reference, contact, or SKU...',
                prefixIcon: const Icon(Icons.search_rounded, size: 20),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear_rounded, size: 18),
                        onPressed: () {
                          _searchController.clear();
                          setState(() => _searchQuery = '');
                        },
                      )
                    : null,
              ),
            ),
          ),

          // Active filter badges
          _buildActiveFiltersBar(),

          // Main Tab View
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                // ==========================================
                // 1. Move History: List View (Section 25)
                // ==========================================
                RefreshIndicator(
                  onRefresh: () async => ref.invalidate(moveHistoryFutureProvider),
                  child: movesAsync.when(
                    loading: () => const LoadingView(message: 'Loading derived moves...'),
                    error: (err, _) => ErrorView(
                      message: err.toString(),
                      onRetry: () => ref.invalidate(moveHistoryFutureProvider),
                    ),
                    data: (moves) {
                      final filtered = _applyMoveFilters(moves);
                      if (filtered.isEmpty) {
                        return const EmptyView(
                          title: 'No Move Records',
                          subtitle: 'Derived inventory transactions will appear here',
                        );
                      }
                      return ListView.separated(
                        padding: AppSpacing.pagePadding,
                        itemCount: filtered.length,
                        separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.sm),
                        itemBuilder: (context, i) => _buildMoveCard(filtered[i]),
                      );
                    },
                  ),
                ),

                // ==========================================
                // 2. Move History: Kanban View (Section 25)
                // ==========================================
                RefreshIndicator(
                  onRefresh: () async => ref.invalidate(moveHistoryFutureProvider),
                  child: movesAsync.when(
                    loading: () => const LoadingView(message: 'Loading Kanban view...'),
                    error: (err, _) => ErrorView(
                      message: err.toString(),
                      onRetry: () => ref.invalidate(moveHistoryFutureProvider),
                    ),
                    data: (moves) {
                      final filtered = _applyMoveFilters(moves);
                      if (filtered.isEmpty) {
                        return const EmptyView(
                          title: 'No Moves for Kanban',
                          subtitle: 'Move items will populate status columns here',
                        );
                      }
                      return Padding(
                        padding: const EdgeInsets.all(12),
                        child: ListView(
                          scrollDirection: Axis.horizontal,
                          children: [
                            _buildKanbanColumn('Draft', 'draft', filtered),
                            _buildKanbanColumn('Waiting', 'waiting', filtered),
                            _buildKanbanColumn('Ready', 'ready', filtered),
                            _buildKanbanColumn('Done', 'done', filtered),
                          ],
                        ),
                      );
                    },
                  ),
                ),

                // ==========================================
                // 3. Stock Ledger: Vertical Timeline (Section 24)
                // ==========================================
                RefreshIndicator(
                  onRefresh: () async => ref.invalidate(ledgerFutureProvider),
                  child: ledgerAsync.when(
                    loading: () => const LoadingView(message: 'Loading immutable stock ledger...'),
                    error: (err, _) => ErrorView(
                      message: err.toString(),
                      onRetry: () => ref.invalidate(ledgerFutureProvider),
                    ),
                    data: (entries) {
                      final filtered = _applyLedgerFilters(entries);
                      return _buildLedgerVerticalTimeline(filtered);
                    },
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
