import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dio/dio.dart';
import '../../core/providers/core_providers.dart';
import '../../core/network/api_endpoints.dart';
import '../../core/network/api_client.dart';
import '../../features/receipts/domain/receipt_verification_models.dart';
export '../../features/receipts/domain/receipt_verification_models.dart';

// ==========================================
// 1. DASHBOARD (SECTION 26 & 27)
// ==========================================
class LowStockItem {
  final int productId;
  final String productName;
  final String sku;
  final String? categoryName;
  final String unitOfMeasure;
  final double costPerUnit;
  final double onHand;
  final double reserved;
  final double freeToUse;
  final double reorderLevel;
  final String status; // "OUT OF STOCK", "LOW STOCK", "NORMAL"

  LowStockItem({
    required this.productId,
    required this.productName,
    required this.sku,
    this.categoryName,
    this.unitOfMeasure = 'unit',
    this.costPerUnit = 0.0,
    required this.onHand,
    required this.reserved,
    required this.freeToUse,
    required this.reorderLevel,
    required this.status,
  });

  factory LowStockItem.fromJson(Map<String, dynamic> json) {
    final onH = (json['on_hand'] as num?)?.toDouble() ?? 0.0;
    final res = (json['reserved'] as num?)?.toDouble() ?? 0.0;
    final free = (json['free_to_use'] as num?)?.toDouble() ?? (onH - res);
    final reorder = (json['reorder_level'] as num?)?.toDouble() ?? 0.0;
    final stat = json['status'] as String? ?? (onH == 0 ? 'OUT OF STOCK' : (onH <= reorder ? 'LOW STOCK' : 'NORMAL'));

    return LowStockItem(
      productId: json['product_id'] as int? ?? 0,
      productName: json['product_name'] as String? ?? '',
      sku: json['sku'] as String? ?? '',
      categoryName: json['category_name'] as String?,
      unitOfMeasure: json['unit_of_measure'] as String? ?? 'unit',
      costPerUnit: (json['cost_per_unit'] as num?)?.toDouble() ?? 0.0,
      onHand: onH,
      reserved: res,
      freeToUse: free,
      reorderLevel: reorder,
      status: stat,
    );
  }
}

class DashboardRecentMovement {
  final int id;
  final String reference;
  final String type;
  final String status;
  final String productName;
  final String sku;
  final double quantity;
  final String? fromLocation;
  final String? toLocation;
  final String? createdAt;

  DashboardRecentMovement({
    required this.id,
    required this.reference,
    required this.type,
    required this.status,
    required this.productName,
    required this.sku,
    required this.quantity,
    this.fromLocation,
    this.toLocation,
    this.createdAt,
  });

  factory DashboardRecentMovement.fromJson(Map<String, dynamic> json) {
    return DashboardRecentMovement(
      id: json['id'] as int? ?? 0,
      reference: json['reference'] as String? ?? '',
      type: json['type'] as String? ?? '',
      status: json['status'] as String? ?? '',
      productName: json['product_name'] as String? ?? '',
      sku: json['sku'] as String? ?? '',
      quantity: (json['quantity'] as num?)?.toDouble() ?? 0.0,
      fromLocation: json['from_location'] as String?,
      toLocation: json['to_location'] as String?,
      createdAt: json['created_at'] as String?,
    );
  }
}

class DashboardIntelligence {
  final double totalStockValue;
  final List<String> fastMovingItems;
  final int deadStockCount;
  final int reorderRecommendedCount;
  final String? topMovingProduct;

  DashboardIntelligence({
    this.totalStockValue = 0.0,
    this.fastMovingItems = const [],
    this.deadStockCount = 0,
    this.reorderRecommendedCount = 0,
    this.topMovingProduct,
  });

  factory DashboardIntelligence.fromJson(Map<String, dynamic> json) {
    final items = (json['fast_moving_items'] as List?)?.map((e) => e.toString()).toList() ?? [];
    return DashboardIntelligence(
      totalStockValue: (json['total_stock_value'] as num?)?.toDouble() ?? 0.0,
      fastMovingItems: items,
      deadStockCount: json['dead_stock_count'] as int? ?? 0,
      reorderRecommendedCount: json['reorder_recommended_count'] as int? ?? 0,
      topMovingProduct: json['top_moving_product'] as String?,
    );
  }
}

class DashboardData {
  final double totalStock;
  final int totalProducts;
  final int lowStockCount;
  final int outOfStockCount;
  final int pendingReceipts;
  final int pendingDeliveries;
  final int waitingDeliveries;
  final int transfersScheduled;
  final List<LowStockItem> lowStockProducts;
  final List<DashboardRecentMovement> recentMovements;
  final DashboardIntelligence intelligence;

  DashboardData({
    required this.totalStock,
    required this.totalProducts,
    required this.lowStockCount,
    required this.outOfStockCount,
    required this.pendingReceipts,
    required this.pendingDeliveries,
    required this.waitingDeliveries,
    required this.transfersScheduled,
    this.lowStockProducts = const [],
    this.recentMovements = const [],
    required this.intelligence,
  });

  factory DashboardData.fromJson(Map<String, dynamic> json) {
    final lowStockList = (json['low_stock_products'] as List?)
            ?.map((e) => LowStockItem.fromJson(e as Map<String, dynamic>))
            .toList() ??
        [];
    final recentList = (json['recent_movements'] as List?)
            ?.map((e) => DashboardRecentMovement.fromJson(e as Map<String, dynamic>))
            .toList() ??
        [];
    final intel = json['intelligence_preview'] != null
        ? DashboardIntelligence.fromJson(json['intelligence_preview'] as Map<String, dynamic>)
        : DashboardIntelligence();

    return DashboardData(
      totalStock: (json['total_stock'] as num?)?.toDouble() ?? 0.0,
      totalProducts: json['total_products'] as int? ?? 0,
      lowStockCount: json['low_stock_count'] as int? ?? (json['low_stock'] as int? ?? 0),
      outOfStockCount: json['out_of_stock_count'] as int? ?? (json['out_of_stock'] as int? ?? 0),
      pendingReceipts: json['pending_receipts'] as int? ?? 0,
      pendingDeliveries: json['pending_deliveries'] as int? ?? 0,
      waitingDeliveries: json['waiting_deliveries'] as int? ?? 0,
      transfersScheduled: json['transfers_scheduled'] as int? ?? 0,
      lowStockProducts: lowStockList,
      recentMovements: recentList,
      intelligence: intel,
    );
  }
}

class DashboardRepository {
  final ApiClient _api;
  DashboardRepository(this._api);

  Future<DashboardData> getDashboard() async {
    final res = await _api.get(ApiEndpoints.dashboardSummary);
    return DashboardData.fromJson(res.data as Map<String, dynamic>);
  }
}

final dashboardRepositoryProvider = Provider<DashboardRepository>((ref) {
  return DashboardRepository(ref.watch(apiClientProvider));
});

final dashboardFutureProvider = FutureProvider<DashboardData>((ref) async {
  return ref.watch(dashboardRepositoryProvider).getDashboard();
});

// ==========================================
// 2. STOCK & PRODUCTS
// ==========================================
class StockItem {
  final int productId;
  final String productName;
  final String sku;
  final double costPerUnit;
  final double onHand;
  final double reserved;
  final double freeToUse;
  final double reorderPoint;
  final bool lowStock;

  final String warehouseName;
  final String locationName;
  final String unitOfMeasure;

  // Section 27 Low Stock rules:
  // if on_hand == 0: OUT OF STOCK
  // elif on_hand <= reorder_level: LOW STOCK
  // else: NORMAL
  String get status {
    if (onHand == 0) return 'OUT OF STOCK';
    if (onHand <= reorderPoint) return 'LOW STOCK';
    return 'NORMAL';
  }

  StockItem({
    required this.productId,
    required this.productName,
    required this.sku,
    required this.costPerUnit,
    required this.onHand,
    required this.reserved,
    required this.freeToUse,
    required this.reorderPoint,
    required this.lowStock,
    this.warehouseName = 'Main Warehouse',
    this.locationName = 'Rack A',
    this.unitOfMeasure = 'kg',
  });

  factory StockItem.fromJson(Map<String, dynamic> json) {
    final onHand = (json['on_hand'] as num?)?.toDouble() ?? 0.0;
    final reserved = (json['reserved'] as num?)?.toDouble() ?? 0.0;
    final freeToUse = (json['free_to_use'] as num?)?.toDouble() ?? (onHand - reserved);
    final reorder = (json['reorder_point'] as num?)?.toDouble() ?? 0.0;
    final isLow = onHand <= reorder;

    return StockItem(
      productId: json['product_id'] as int? ?? 0,
      productName: json['product_name'] as String? ?? '',
      sku: json['sku'] as String? ?? '',
      costPerUnit: (json['cost_per_unit'] as num?)?.toDouble() ?? 0.0,
      onHand: onHand,
      reserved: reserved,
      freeToUse: freeToUse,
      reorderPoint: reorder,
      lowStock: isLow,
      warehouseName: json['warehouse_name'] as String? ?? 'Main Warehouse',
      locationName: json['location_name'] as String? ?? 'Rack A',
      unitOfMeasure: json['unit_of_measure'] as String? ?? 'kg',
    );
  }
}

class StockRepository {
  final ApiClient _api;
  StockRepository(this._api);

  Future<List<StockItem>> getStock({int? locationId}) async {
    final path = locationId != null ? '${ApiEndpoints.stock}?location_id=$locationId' : ApiEndpoints.stock;
    final res = await _api.get(path);
    final list = res.data as List? ?? [];
    return list.map((e) => StockItem.fromJson(e as Map<String, dynamic>)).toList();
  }
}

final stockRepositoryProvider = Provider<StockRepository>((ref) {
  return StockRepository(ref.watch(apiClientProvider));
});

final stockFutureProvider = FutureProvider<List<StockItem>>((ref) async {
  return ref.watch(stockRepositoryProvider).getStock();
});

// ==========================================
// 3. MOVE HISTORY & LEDGER (SECTIONS 24 & 25)
// ==========================================

class StockLedgerItem {
  final int id;
  final int? transactionId;
  final int productId;
  final String productName;
  final String sku;
  final int locationId;
  final String locationName;
  final String? warehouseName;
  final double quantityBefore;
  final double quantityChange;
  final double quantityAfter;
  final String movementType;
  final String? reference;
  final String createdAt;

  StockLedgerItem({
    required this.id,
    this.transactionId,
    required this.productId,
    required this.productName,
    required this.sku,
    required this.locationId,
    required this.locationName,
    this.warehouseName,
    required this.quantityBefore,
    required this.quantityChange,
    required this.quantityAfter,
    required this.movementType,
    this.reference,
    required this.createdAt,
  });

  factory StockLedgerItem.fromJson(Map<String, dynamic> json) {
    return StockLedgerItem(
      id: json['id'] as int? ?? 0,
      transactionId: json['transaction_id'] as int?,
      productId: json['product_id'] as int? ?? 0,
      productName: json['product_name'] as String? ?? '',
      sku: json['sku'] as String? ?? '',
      locationId: json['location_id'] as int? ?? 0,
      locationName: json['location_name'] as String? ?? '',
      warehouseName: json['warehouse_name'] as String?,
      quantityBefore: (json['quantity_before'] as num?)?.toDouble() ?? 0.0,
      quantityChange: (json['quantity_change'] as num?)?.toDouble() ?? 0.0,
      quantityAfter: (json['quantity_after'] as num?)?.toDouble() ?? 0.0,
      movementType: json['movement_type'] as String? ?? 'RECEIPT',
      reference: json['reference'] as String?,
      createdAt: json['created_at'] as String? ?? '',
    );
  }
}

class StockMoveItem {
  final int id;
  final String reference;
  final String moveType;
  final int productId;
  final String productName;
  final String sku;
  final int fromLocationId;
  final String fromLocationName;
  final int toLocationId;
  final String toLocationName;
  final double quantity;
  final String status;
  final String? contact;
  final String? createdAt;
  final String? doneAt;
  final String? date;
  final List<StockLedgerItem>? ledgerEntries;
  // Section 20 Metrics: On Hand, Reserved, Free to Use, Requested, Shortage
  final double onHand;
  final double reserved;
  final double freeToUse;
  final double requested;
  final double shortage;
  final bool isWaitingForStock;
  // Section 23 Adjustment fields
  final double? systemQuantity;
  final double? physicalCount;
  final double? difference;
  final String? reason;

  StockMoveItem({
    required this.id,
    required this.reference,
    required this.moveType,
    required this.productId,
    required this.productName,
    required this.sku,
    required this.fromLocationId,
    required this.fromLocationName,
    required this.toLocationId,
    required this.toLocationName,
    required this.quantity,
    required this.status,
    this.contact,
    this.createdAt,
    this.doneAt,
    this.date,
    this.ledgerEntries,
    this.onHand = 0.0,
    this.reserved = 0.0,
    this.freeToUse = 0.0,
    this.requested = 0.0,
    this.shortage = 0.0,
    this.isWaitingForStock = false,
    this.systemQuantity,
    this.physicalCount,
    this.difference,
    this.reason,
  });

  factory StockMoveItem.fromJson(Map<String, dynamic> json) {
    final qty = (json['quantity'] as num?)?.toDouble() ?? 0.0;
    final onH = (json['on_hand'] as num?)?.toDouble() ?? 0.0;
    final res = (json['reserved'] as num?)?.toDouble() ?? 0.0;
    final free = (json['free_to_use'] as num?)?.toDouble() ?? (onH - res);
    final req = (json['requested'] as num?)?.toDouble() ?? qty;
    final stat = (json['status'] as String? ?? 'draft').toLowerCase();
    final short = (json['shortage'] as num?)?.toDouble() ?? 0.0;
    final isWaiting = (json['is_waiting_for_stock'] as bool?) ?? (stat == 'waiting');

    final sysQty = (json['system_quantity'] as num?)?.toDouble();
    final physCount = (json['physical_count'] as num?)?.toDouble();
    final diff = (json['difference'] as num?)?.toDouble();
    final reasonStr = json['reason'] as String?;

    final moveTypeVal = json['move_type'] as String? ?? json['type'] as String? ?? '';
    final fromLocName = json['from_location_name'] as String? ?? json['from_location'] as String? ?? (json['location_name'] as String? ?? '');
    final toLocName = json['to_location_name'] as String? ?? json['to_location'] as String? ?? '';
    final dateVal = json['date'] as String? ?? json['created_at'] as String?;
    final entries = (json['ledger_entries'] as List?)
        ?.map((e) => StockLedgerItem.fromJson(e as Map<String, dynamic>))
        .toList();

    return StockMoveItem(
      id: json['id'] as int? ?? 0,
      reference: json['reference'] as String? ?? '',
      moveType: moveTypeVal,
      productId: json['product_id'] as int? ?? 0,
      productName: json['product_name'] as String? ?? '',
      sku: json['sku'] as String? ?? '',
      fromLocationId: json['from_location_id'] as int? ?? (json['location_id'] as int? ?? 0),
      fromLocationName: fromLocName,
      toLocationId: json['to_location_id'] as int? ?? 0,
      toLocationName: toLocName,
      quantity: qty,
      status: stat,
      contact: json['contact'] as String?,
      createdAt: json['created_at'] as String?,
      doneAt: json['done_at'] as String?,
      date: dateVal,
      ledgerEntries: entries,
      onHand: onH,
      reserved: res,
      freeToUse: free,
      requested: req,
      shortage: short,
      isWaitingForStock: isWaiting,
      systemQuantity: sysQty,
      physicalCount: physCount,
      difference: diff,
      reason: reasonStr,
    );
  }
}

class MoveHistoryRepository {
  final ApiClient _api;
  MoveHistoryRepository(this._api);

  Future<List<StockMoveItem>> getMoves({
    String? type,
    String? status,
    String? search,
    int? productId,
    int? warehouseId,
    int? locationId,
    String? dateFrom,
    String? dateTo,
  }) async {
    final params = <String, dynamic>{};
    if (type != null && type.isNotEmpty) params['type'] = type;
    if (status != null && status.isNotEmpty) params['status'] = status;
    if (search != null && search.isNotEmpty) params['search'] = search;
    if (productId != null) params['product_id'] = productId;
    if (warehouseId != null) params['warehouse_id'] = warehouseId;
    if (locationId != null) params['location_id'] = locationId;
    if (dateFrom != null) params['date_from'] = dateFrom;
    if (dateTo != null) params['date_to'] = dateTo;

    final res = await _api.get(ApiEndpoints.moves, queryParameters: params);
    final list = res.data as List? ?? [];
    return list.map((e) => StockMoveItem.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<List<StockMoveItem>> getMoveHistory({
    String? moveType,
    String? status,
    String? search,
    int? productId,
    int? warehouseId,
    int? locationId,
    String? dateFrom,
    String? dateTo,
  }) async {
    return getMoves(
      type: moveType,
      status: status,
      search: search,
      productId: productId,
      warehouseId: warehouseId,
      locationId: locationId,
      dateFrom: dateFrom,
      dateTo: dateTo,
    );
  }
}

final moveHistoryRepositoryProvider = Provider<MoveHistoryRepository>((ref) {
  return MoveHistoryRepository(ref.watch(apiClientProvider));
});

final moveHistoryFutureProvider = FutureProvider<List<StockMoveItem>>((ref) async {
  return ref.watch(moveHistoryRepositoryProvider).getMoveHistory();
});

class LedgerRepository {
  final ApiClient _api;
  LedgerRepository(this._api);

  Future<List<StockLedgerItem>> getLedger({
    int? productId,
    int? locationId,
    String? movementType,
    int? transactionId,
  }) async {
    final params = <String, dynamic>{};
    if (productId != null) params['product_id'] = productId;
    if (locationId != null) params['location_id'] = locationId;
    if (movementType != null && movementType.isNotEmpty) params['movement_type'] = movementType;
    if (transactionId != null) params['transaction_id'] = transactionId;

    final res = await _api.get(ApiEndpoints.ledger, queryParameters: params);
    final list = res.data as List? ?? [];
    return list.map((e) => StockLedgerItem.fromJson(e as Map<String, dynamic>)).toList();
  }
}

final ledgerRepositoryProvider = Provider<LedgerRepository>((ref) {
  return LedgerRepository(ref.watch(apiClientProvider));
});

final ledgerFutureProvider = FutureProvider<List<StockLedgerItem>>((ref) async {
  return ref.watch(ledgerRepositoryProvider).getLedger();
});

// ==========================================
// 4. OPERATIONS (RECEIPTS, DELIVERIES, TRANSFERS, ADJUSTMENTS)
// ==========================================
class ReceiptsRepository {
  final ApiClient _api;
  ReceiptsRepository(this._api);

  Future<List<StockMoveItem>> getReceipts() async {
    final res = await _api.get(ApiEndpoints.receipts);
    final list = res.data as List? ?? [];
    return list.map((e) => StockMoveItem.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<StockMoveItem> createReceipt(Map<String, dynamic> payload) async {
    final res = await _api.post(ApiEndpoints.receipts, data: payload);
    return StockMoveItem.fromJson(res.data as Map<String, dynamic>);
  }

  Future<StockMoveItem> markReady(int id) async {
    final res = await _api.post(ApiEndpoints.readyReceipt(id));
    return StockMoveItem.fromJson(res.data as Map<String, dynamic>);
  }

  Future<StockMoveItem> validateReceipt(int id) async {
    final res = await _api.post(ApiEndpoints.validateReceipt(id));
    return StockMoveItem.fromJson(res.data as Map<String, dynamic>);
  }

  Future<StockMoveItem> cancelReceipt(int id) async {
    final res = await _api.post(ApiEndpoints.cancelReceipt(id));
    return StockMoveItem.fromJson(res.data as Map<String, dynamic>);
  }

  // Physical Receipt Document & OCR Verification (Sections 26-30, 40)
  Future<ReceiptDocumentMeta> uploadReceiptDocument(
    int id, {
    required String fileName,
    required List<int> bytes,
    String mimeType = 'application/pdf',
  }) async {
    final formData = FormData.fromMap({
      'file': MultipartFile.fromBytes(bytes, filename: fileName),
    });
    final res = await _api.post(
      ApiEndpoints.receiptDocument(id),
      data: formData,
    );
    final data = res.data as Map<String, dynamic>;
    return ReceiptDocumentMeta.fromJson(data['document'] as Map<String, dynamic>);
  }

  Future<ReceiptVerificationResult> verifyReceiptDocument(int id) async {
    final res = await _api.post(ApiEndpoints.verifyReceiptDocument(id));
    final data = res.data as Map<String, dynamic>;
    return ReceiptVerificationResult.fromJson(data['verification'] as Map<String, dynamic>);
  }

  Future<ReceiptVerificationResult?> getReceiptVerification(int id) async {
    try {
      final res = await _api.get(ApiEndpoints.receiptVerification(id));
      final data = res.data as Map<String, dynamic>;
      if (data['verification'] != null) {
        return ReceiptVerificationResult.fromJson(data['verification'] as Map<String, dynamic>);
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  Future<ReceiptDocumentMeta?> getReceiptDocument(int id) async {
    try {
      final res = await _api.get(ApiEndpoints.receiptDocument(id));
      final data = res.data as Map<String, dynamic>;
      if (data['document'] != null) {
        return ReceiptDocumentMeta.fromJson(data['document'] as Map<String, dynamic>);
      }
      return null;
    } catch (_) {
      return null;
    }
  }
}

final receiptsRepositoryProvider = Provider<ReceiptsRepository>((ref) {
  return ReceiptsRepository(ref.watch(apiClientProvider));
});

final receiptsFutureProvider = FutureProvider<List<StockMoveItem>>((ref) async {
  return ref.watch(receiptsRepositoryProvider).getReceipts();
});

final receiptVerificationFutureProvider =
    FutureProvider.family<ReceiptVerificationResult?, int>((ref, receiptId) async {
  return ref.watch(receiptsRepositoryProvider).getReceiptVerification(receiptId);
});

final receiptDocumentFutureProvider =
    FutureProvider.family<ReceiptDocumentMeta?, int>((ref, receiptId) async {
  return ref.watch(receiptsRepositoryProvider).getReceiptDocument(receiptId);
});


class DeliveriesRepository {
  final ApiClient _api;
  DeliveriesRepository(this._api);

  Future<List<StockMoveItem>> getDeliveries() async {
    final res = await _api.get(ApiEndpoints.deliveries);
    final list = res.data as List? ?? [];
    return list.map((e) => StockMoveItem.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<StockMoveItem> createDelivery(Map<String, dynamic> payload) async {
    final res = await _api.post(ApiEndpoints.deliveries, data: payload);
    return StockMoveItem.fromJson(res.data as Map<String, dynamic>);
  }

  Future<StockMoveItem> markReady(int id) async {
    final res = await _api.post(ApiEndpoints.readyDelivery(id));
    return StockMoveItem.fromJson(res.data as Map<String, dynamic>);
  }

  Future<StockMoveItem> validateDelivery(int id) async {
    final res = await _api.post(ApiEndpoints.validateDelivery(id));
    return StockMoveItem.fromJson(res.data as Map<String, dynamic>);
  }

  Future<StockMoveItem> cancelDelivery(int id) async {
    final res = await _api.post(ApiEndpoints.cancelDelivery(id));
    return StockMoveItem.fromJson(res.data as Map<String, dynamic>);
  }

  Future<Map<String, dynamic>> processWaiting() async {
    final res = await _api.post(ApiEndpoints.processWaitingDeliveries);
    return res.data as Map<String, dynamic>;
  }
}

final deliveriesRepositoryProvider = Provider<DeliveriesRepository>((ref) {
  return DeliveriesRepository(ref.watch(apiClientProvider));
});

final deliveriesFutureProvider = FutureProvider<List<StockMoveItem>>((ref) async {
  return ref.watch(deliveriesRepositoryProvider).getDeliveries();
});

class TransfersRepository {
  final ApiClient _api;
  TransfersRepository(this._api);

  Future<List<StockMoveItem>> getTransfers() async {
    final res = await _api.get(ApiEndpoints.transfers);
    final list = res.data as List? ?? [];
    return list.map((e) => StockMoveItem.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<StockMoveItem> createTransfer(Map<String, dynamic> payload) async {
    final res = await _api.post(ApiEndpoints.transfers, data: payload);
    return StockMoveItem.fromJson(res.data as Map<String, dynamic>);
  }

  Future<StockMoveItem> markReady(int id) async {
    final res = await _api.post(ApiEndpoints.readyTransfer(id));
    return StockMoveItem.fromJson(res.data as Map<String, dynamic>);
  }

  Future<StockMoveItem> validateTransfer(int id) async {
    final res = await _api.post(ApiEndpoints.validateTransfer(id));
    return StockMoveItem.fromJson(res.data as Map<String, dynamic>);
  }

  Future<StockMoveItem> cancelTransfer(int id) async {
    final res = await _api.post(ApiEndpoints.cancelTransfer(id));
    return StockMoveItem.fromJson(res.data as Map<String, dynamic>);
  }
}

final transfersRepositoryProvider = Provider<TransfersRepository>((ref) {
  return TransfersRepository(ref.watch(apiClientProvider));
});

final transfersFutureProvider = FutureProvider<List<StockMoveItem>>((ref) async {
  return ref.watch(transfersRepositoryProvider).getTransfers();
});

class AdjustmentsRepository {
  final ApiClient _api;
  AdjustmentsRepository(this._api);

  Future<List<StockMoveItem>> getAdjustments() async {
    final res = await _api.get(ApiEndpoints.adjustments);
    final list = res.data as List? ?? [];
    return list.map((e) => StockMoveItem.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<StockMoveItem> createAdjustment(Map<String, dynamic> payload) async {
    final res = await _api.post(ApiEndpoints.adjustments, data: payload);
    return StockMoveItem.fromJson(res.data as Map<String, dynamic>);
  }

  Future<StockMoveItem> validateAdjustment(int id) async {
    final res = await _api.post(ApiEndpoints.validateAdjustment(id));
    return StockMoveItem.fromJson(res.data as Map<String, dynamic>);
  }

  Future<StockMoveItem> cancelAdjustment(int id) async {
    final res = await _api.post(ApiEndpoints.cancelAdjustment(id));
    return StockMoveItem.fromJson(res.data as Map<String, dynamic>);
  }
}

final adjustmentsRepositoryProvider = Provider<AdjustmentsRepository>((ref) {
  return AdjustmentsRepository(ref.watch(apiClientProvider));
});

final adjustmentsFutureProvider = FutureProvider<List<StockMoveItem>>((ref) async {
  return ref.watch(adjustmentsRepositoryProvider).getAdjustments();
});

// ==========================================
// 5. MASTER DATA (PRODUCTS, WAREHOUSES, LOCATIONS)
// ==========================================
class MasterDataRepository {
  final ApiClient _api;
  MasterDataRepository(this._api);

  Future<List<dynamic>> getProducts() async {
    final res = await _api.get(ApiEndpoints.products);
    return res.data as List? ?? [];
  }

  Future<List<dynamic>> getCategories() async {
    final res = await _api.get(ApiEndpoints.categories);
    return res.data as List? ?? [];
  }

  Future<List<dynamic>> getWarehouses() async {
    final res = await _api.get(ApiEndpoints.warehouses);
    return res.data as List? ?? [];
  }

  Future<List<dynamic>> getLocations() async {
    final res = await _api.get(ApiEndpoints.locations);
    return res.data as List? ?? [];
  }
}

final masterDataRepositoryProvider = Provider<MasterDataRepository>((ref) {
  return MasterDataRepository(ref.watch(apiClientProvider));
});

final productsFutureProvider = FutureProvider<List<dynamic>>((ref) async {
  return ref.watch(masterDataRepositoryProvider).getProducts();
});

final warehousesFutureProvider = FutureProvider<List<dynamic>>((ref) async {
  return ref.watch(masterDataRepositoryProvider).getWarehouses();
});

final locationsFutureProvider = FutureProvider<List<dynamic>>((ref) async {
  return ref.watch(masterDataRepositoryProvider).getLocations();
});

// ==========================================
// 6. INVENTORY INTELLIGENCE (SECTION 28)
// ==========================================
class StockoutPredictionItem {
  final int productId;
  final String productName;
  final String sku;
  final double currentStock;
  final double? averageDailyUsage;
  final double reorderLevel;
  final double? estimatedDaysToReorder;
  final double? estimatedDaysToStockout;
  final bool hasSufficientHistory;
  final String? message;

  StockoutPredictionItem({
    required this.productId,
    required this.productName,
    required this.sku,
    required this.currentStock,
    this.averageDailyUsage,
    required this.reorderLevel,
    this.estimatedDaysToReorder,
    this.estimatedDaysToStockout,
    required this.hasSufficientHistory,
    this.message,
  });

  factory StockoutPredictionItem.fromJson(Map<String, dynamic> json) {
    return StockoutPredictionItem(
      productId: json['product_id'] as int? ?? 0,
      productName: json['product_name'] as String? ?? '',
      sku: json['sku'] as String? ?? '',
      currentStock: (json['current_stock'] as num?)?.toDouble() ?? 0.0,
      averageDailyUsage: (json['average_daily_usage'] as num?)?.toDouble(),
      reorderLevel: (json['reorder_level'] as num?)?.toDouble() ?? 0.0,
      estimatedDaysToReorder: (json['estimated_days_to_reorder'] as num?)?.toDouble(),
      estimatedDaysToStockout: (json['estimated_days_to_stockout'] as num?)?.toDouble(),
      hasSufficientHistory: json['has_sufficient_history'] as bool? ?? false,
      message: json['message'] as String?,
    );
  }
}

class ReorderRecommendationItem {
  final int productId;
  final String productName;
  final String sku;
  final double currentStock;
  final double? averageUsage;
  final int targetCoverage;
  final double recommendedReorderQuantity;
  final String explanation;
  final bool hasSufficientHistory;
  final String? message;

  ReorderRecommendationItem({
    required this.productId,
    required this.productName,
    required this.sku,
    required this.currentStock,
    this.averageUsage,
    this.targetCoverage = 30,
    required this.recommendedReorderQuantity,
    required this.explanation,
    required this.hasSufficientHistory,
    this.message,
  });

  factory ReorderRecommendationItem.fromJson(Map<String, dynamic> json) {
    return ReorderRecommendationItem(
      productId: json['product_id'] as int? ?? 0,
      productName: json['product_name'] as String? ?? '',
      sku: json['sku'] as String? ?? '',
      currentStock: (json['current_stock'] as num?)?.toDouble() ?? 0.0,
      averageUsage: (json['average_usage'] as num?)?.toDouble(),
      targetCoverage: json['target_coverage'] as int? ?? 30,
      recommendedReorderQuantity: (json['recommended_reorder_quantity'] as num?)?.toDouble() ?? 0.0,
      explanation: json['explanation'] as String? ?? '',
      hasSufficientHistory: json['has_sufficient_history'] as bool? ?? false,
      message: json['message'] as String?,
    );
  }
}

class IntelligenceRepository {
  final ApiClient _api;
  IntelligenceRepository(this._api);

  Future<List<StockoutPredictionItem>> getStockoutPredictions({int? productId}) async {
    final path = productId != null
        ? '${ApiEndpoints.stockoutIntelligence}?product_id=$productId'
        : ApiEndpoints.stockoutIntelligence;
    final res = await _api.get(path);
    final list = res.data as List? ?? [];
    return list.map((e) => StockoutPredictionItem.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<List<ReorderRecommendationItem>> getReorderRecommendations({
    int targetCoverage = 30,
    int? productId,
  }) async {
    var path = '${ApiEndpoints.reorderIntelligence}?target_coverage=$targetCoverage';
    if (productId != null) {
      path += '&product_id=$productId';
    }
    final res = await _api.get(path);
    final list = res.data as List? ?? [];
    return list.map((e) => ReorderRecommendationItem.fromJson(e as Map<String, dynamic>)).toList();
  }
}

final intelligenceRepositoryProvider = Provider<IntelligenceRepository>((ref) {
  return IntelligenceRepository(ref.watch(apiClientProvider));
});

final stockoutFutureProvider = FutureProvider<List<StockoutPredictionItem>>((ref) async {
  return ref.watch(intelligenceRepositoryProvider).getStockoutPredictions();
});

class TargetCoverageNotifier extends Notifier<int> {
  @override
  int build() => 30;

  void setCoverage(int days) {
    state = days;
  }
}

final reorderTargetCoverageProvider =
    NotifierProvider<TargetCoverageNotifier, int>(TargetCoverageNotifier.new);

final reorderFutureProvider = FutureProvider<List<ReorderRecommendationItem>>((ref) async {
  final coverage = ref.watch(reorderTargetCoverageProvider);
  return ref.watch(intelligenceRepositoryProvider).getReorderRecommendations(targetCoverage: coverage);
});

