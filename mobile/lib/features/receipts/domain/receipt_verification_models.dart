class ReceiptDocumentMeta {
  final int id;
  final int transactionId;
  final String originalFilename;
  final String mimeType;
  final int fileSize;
  final int pageCount;
  final String ocrStatus;
  final double? ocrConfidence;
  final String? uploadedAt;
  final String? processedAt;

  ReceiptDocumentMeta({
    required this.id,
    required this.transactionId,
    required this.originalFilename,
    required this.mimeType,
    required this.fileSize,
    required this.pageCount,
    required this.ocrStatus,
    this.ocrConfidence,
    this.uploadedAt,
    this.processedAt,
  });

  factory ReceiptDocumentMeta.fromJson(Map<String, dynamic> json) {
    return ReceiptDocumentMeta(
      id: json['id'] as int? ?? 0,
      transactionId: json['transaction_id'] as int? ?? 0,
      originalFilename: json['original_filename'] as String? ?? 'receipt',
      mimeType: json['mime_type'] as String? ?? 'application/pdf',
      fileSize: json['file_size'] as int? ?? 0,
      pageCount: json['page_count'] as int? ?? 1,
      ocrStatus: json['ocr_status'] as String? ?? 'UPLOADED',
      ocrConfidence: (json['ocr_confidence'] as num?)?.toDouble(),
      uploadedAt: json['uploaded_at'] as String?,
      processedAt: json['processed_at'] as String?,
    );
  }

  String get formattedFileSize {
    if (fileSize < 1024) return '$fileSize B';
    if (fileSize < 1024 * 1024) return '${(fileSize / 1024).toStringAsFixed(1)} KB';
    return '${(fileSize / (1024 * 1024)).toStringAsFixed(2)} MB';
  }
}

class VerificationItem {
  final int? productId;
  final String? productName;
  final String status; // MATCH, MISMATCH, NOT_FOUND
  final double systemQuantity;
  final double? ocrQuantity;
  final double? difference;
  final String? systemUnit;
  final String? ocrUnit;
  final String? notes;

  VerificationItem({
    this.productId,
    this.productName,
    required this.status,
    required this.systemQuantity,
    this.ocrQuantity,
    this.difference,
    this.systemUnit,
    this.ocrUnit,
    this.notes,
  });

  /// The backend returns items with `system_unit` and `ocr_unit` fields.
  /// The `unit` field is not present at the item level in the response.
  factory VerificationItem.fromJson(Map<String, dynamic> json) {
    return VerificationItem(
      productId: json['product_id'] as int?,
      productName: json['product_name'] as String?,
      status: json['status'] as String? ?? 'UNKNOWN',
      systemQuantity: (json['system_quantity'] as num?)?.toDouble() ?? 0.0,
      ocrQuantity: (json['ocr_quantity'] as num?)?.toDouble(),
      difference: (json['difference'] as num?)?.toDouble(),
      // Backend returns `system_unit` and `ocr_unit`, not a single `unit`
      systemUnit: json['system_unit'] as String?,
      ocrUnit: json['ocr_unit'] as String?,
      notes: json['notes'] as String?,
    );
  }

  /// Display unit: prefer the system unit, fall back to ocr unit
  String get unit => systemUnit ?? ocrUnit ?? 'units';

  bool get isMatch => status == 'MATCH';
  bool get isMismatch => status == 'MISMATCH';
}

class ReceiptVerificationResult {
  final String status; // MATCH, REVIEW_REQUIRED, LOW_CONFIDENCE, FAILED
  final double confidence;
  final String? supplierStatus;
  final String? supplierSystem;
  final String? supplierOcr;
  final String? receiptNumberStatus;
  final String? receiptNumberSystem;
  final String? receiptNumberOcr;
  // receipt_date is {"system": ..., "ocr": ...} from the backend
  final String? receiptDateSystem;
  final String? receiptDateOcr;
  final List<VerificationItem> items;
  final List<String> issues;
  final Map<String, dynamic>? rawExtracted;

  ReceiptVerificationResult({
    required this.status,
    required this.confidence,
    this.supplierStatus,
    this.supplierSystem,
    this.supplierOcr,
    this.receiptNumberStatus,
    this.receiptNumberSystem,
    this.receiptNumberOcr,
    this.receiptDateSystem,
    this.receiptDateOcr,
    required this.items,
    required this.issues,
    this.rawExtracted,
  });

  factory ReceiptVerificationResult.fromJson(Map<String, dynamic> json) {
    // `supplier` is {"status": ..., "system": ..., "ocr": ...}
    final sup = json['supplier'];
    final Map<String, dynamic>? supMap =
        sup is Map<String, dynamic> ? sup : null;

    // `receipt_number` is {"status": ..., "system": ..., "ocr": ...}
    final rcptNum = json['receipt_number'];
    final Map<String, dynamic>? rcptNumMap =
        rcptNum is Map<String, dynamic> ? rcptNum : null;

    // `receipt_date` is {"system": ..., "ocr": ...} — NOT a plain String
    final rcptDate = json['receipt_date'];
    String? receiptDateSystem;
    String? receiptDateOcr;
    if (rcptDate is Map<String, dynamic>) {
      receiptDateSystem = rcptDate['system'] as String?;
      receiptDateOcr = rcptDate['ocr'] as String?;
    } else if (rcptDate is String) {
      // Defensive fallback in case backend ever returns a plain string
      receiptDateOcr = rcptDate;
    }

    final itemsList = (json['items'] as List?)
            ?.map((e) => VerificationItem.fromJson(e as Map<String, dynamic>))
            .toList() ??
        [];

    final issuesList =
        (json['issues'] as List?)?.map((e) => e.toString()).toList() ?? [];

    return ReceiptVerificationResult(
      status: json['status'] as String? ?? 'UNKNOWN',
      confidence: (json['confidence'] as num?)?.toDouble() ?? 0.0,
      supplierStatus: supMap?['status'] as String?,
      supplierSystem: supMap?['system'] as String?,
      supplierOcr: supMap?['ocr'] as String?,
      receiptNumberStatus: rcptNumMap?['status'] as String?,
      receiptNumberSystem: rcptNumMap?['system'] as String?,
      receiptNumberOcr: rcptNumMap?['ocr'] as String?,
      receiptDateSystem: receiptDateSystem,
      receiptDateOcr: receiptDateOcr,
      items: itemsList,
      issues: issuesList,
      rawExtracted: json['extracted_document'] as Map<String, dynamic>?,
    );
  }

  /// Convenience getter: the OCR-extracted receipt date (most relevant for display)
  String? get receiptDate => receiptDateOcr ?? receiptDateSystem;

  bool get isMatch => status == 'MATCH';
  bool get isReviewRequired => status == 'REVIEW_REQUIRED';
  bool get isLowConfidence => status == 'LOW_CONFIDENCE';
  bool get isFailed => status == 'FAILED';
}
