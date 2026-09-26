class ApiEndpoints {
  ApiEndpoints._();

  // Android emulator uses 10.0.2.2 to access host machine; Windows/Linux uses 127.0.0.1
  static const String defaultBaseUrl = 'http://10.0.2.2:8000';
  static const String localhostBaseUrl = 'http://127.0.0.1:8000';

  // Auth (Section 5)
  static const String register = '/api/auth/register';
  static const String signup = '/api/auth/register';
  static const String login = '/api/auth/login';
  static const String loginJson = '/api/auth/login';
  static const String forgotPassword = '/api/auth/forgot-password';
  static const String resetPassword = '/api/auth/reset-password';
  static const String me = '/api/auth/me';

  // Dashboard (Section 26)
  static const String dashboard = '/dashboard';
  static const String dashboardSummary = '/dashboard/summary';

  // Master Data
  static const String products = '/products';
  static const String categories = '/categories';
  static const String warehouses = '/warehouses';
  static const String locations = '/warehouses/locations';

  // Inventory Engine & Stock
  static const String stock = '/stock';

  // Operations
  static const String receipts = '/receipts';
  static String readyReceipt(int id) => '/receipts/$id/ready';
  static String validateReceipt(int id) => '/receipts/$id/validate';
  static String cancelReceipt(int id) => '/receipts/$id/cancel';
  static String receiptDocument(int id) => '/receipts/$id/receipt-document';
  static String verifyReceiptDocument(int id) => '/receipts/$id/receipt-document/verify';
  static String receiptVerification(int id) => '/receipts/$id/receipt-verification';


  static const String deliveries = '/deliveries';
  static String readyDelivery(int id) => '/deliveries/$id/ready';
  static String validateDelivery(int id) => '/deliveries/$id/validate';
  static String cancelDelivery(int id) => '/deliveries/$id/cancel';
  static const String processWaitingDeliveries = '/deliveries/process-waiting';

  static const String transfers = '/transfers';
  static String readyTransfer(int id) => '/transfers/$id/ready';
  static String validateTransfer(int id) => '/transfers/$id/validate';
  static String cancelTransfer(int id) => '/transfers/$id/cancel';

  static const String adjustments = '/adjustments';
  static String validateAdjustment(int id) => '/adjustments/$id/validate';
  static String cancelAdjustment(int id) => '/adjustments/$id/cancel';

  // Ledger & History (Section 24 & 25)
  static const String moves = '/moves';
  static const String ledger = '/ledger';
  static const String moveHistory = '/move-history';
  static String lastIncoming(int productId) => '/move-history/last-incoming/$productId';

  // Inventory Intelligence (Section 28)
  static const String stockoutIntelligence = '/intelligence/stockout';
  static const String reorderIntelligence = '/intelligence/reorder';
}
