import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:stocksense_mobile/features/auth/presentation/auth_provider.dart';
import 'package:stocksense_mobile/features/dashboard/presentation/dashboard_screen.dart';
import 'package:stocksense_mobile/features/operations/presentation/operations_screen.dart';
import 'package:stocksense_mobile/features/receipts/presentation/receipt_list_screen.dart';
import 'package:stocksense_mobile/features/deliveries/presentation/delivery_list_screen.dart';
import 'package:stocksense_mobile/features/transfers/presentation/transfer_list_screen.dart';
import 'package:stocksense_mobile/features/move_history/presentation/history_screen.dart';
import 'package:stocksense_mobile/shared/providers/inventory_providers.dart';

class MockAuthNotifier extends AuthNotifier {
  final AuthUser? initialUser;
  MockAuthNotifier({this.initialUser});

  @override
  AuthState build() {
    return AuthState(
      isAuthenticated: initialUser != null,
      user: initialUser,
      isLoading: false,
    );
  }
}

final mockDashboard = DashboardData(
  totalStock: 3500.0,
  lowStockCount: 2,
  outOfStockCount: 1,
  pendingReceipts: 4,
  pendingDeliveries: 3,
  waitingDeliveries: 1,
  transfersScheduled: 2,
  totalProducts: 45,
  lowStockProducts: [],
  recentMovements: [
    DashboardRecentMovement(
      id: 1,
      reference: 'WH/IN/0001',
      type: 'RECEIPT',
      status: 'DONE',
      productName: 'Raw Steel',
      sku: 'STL-01',
      quantity: 100.0,
    ),
    DashboardRecentMovement(
      id: 2,
      reference: 'WH/OUT/0001',
      type: 'DELIVERY',
      status: 'DONE',
      productName: 'Steel Rods',
      sku: 'ROD-01',
      quantity: 20.0,
    ),
  ],
  intelligence: DashboardIntelligence(
    totalStockValue: 50000.0,
    fastMovingItems: ['Raw Steel'],
    deadStockCount: 0,
    reorderRecommendedCount: 2,
  ),
);

void main() {
  group('Post-Signup Navigation & Feature Routing Tests', () {
    testWidgets('1. Home -> Receipt card pushes ReceiptListScreen (NOT Operator Dashboard)', (tester) async {
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final router = GoRouter(
        initialLocation: '/home',
        routes: [
          GoRoute(
            path: '/home',
            builder: (context, state) => const DashboardScreen(),
          ),
          GoRoute(
            path: '/receipts',
            builder: (context, state) => const ReceiptListScreen(),
          ),
          GoRoute(
            path: '/deliveries',
            builder: (context, state) => const DeliveryListScreen(),
          ),
          GoRoute(
            path: '/operations',
            builder: (context, state) => const OperationsScreen(),
          ),
        ],
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            dashboardFutureProvider.overrideWith((ref) async => mockDashboard),
            receiptsFutureProvider.overrideWith((ref) async => []),
            deliveriesFutureProvider.overrideWith((ref) async => []),
            authProvider.overrideWith(() => MockAuthNotifier(
              initialUser: const AuthUser(id: 1, name: 'Warehouse Operator', email: 'op@stocksense.com', role: 'WAREHOUSE_STAFF'),
            )),
          ],
          child: MaterialApp.router(routerConfig: router),
        ),
      );

      await tester.pumpAndSettle();

      // Verify we are on Dashboard
      expect(find.text('StockSense'), findsOneWidget);
      expect(find.text('Receipts'), findsOneWidget);

      // Tap Receipts hero card
      await tester.tap(find.text('Receipts'));
      await tester.pumpAndSettle();

      // VERIFY: We are on Inbound Receipts screen, NOT OperationsScreen / Operator Dashboard
      expect(find.text('Inbound Receipts'), findsOneWidget);
      expect(find.byType(ReceiptListScreen), findsOneWidget);
      expect(find.byType(OperationsScreen), findsNothing);
    });

    testWidgets('2. Home -> Delivery card pushes DeliveryListScreen (NOT Operator Dashboard)', (tester) async {
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final router = GoRouter(
        initialLocation: '/home',
        routes: [
          GoRoute(
            path: '/home',
            builder: (context, state) => const DashboardScreen(),
          ),
          GoRoute(
            path: '/receipts',
            builder: (context, state) => const ReceiptListScreen(),
          ),
          GoRoute(
            path: '/deliveries',
            builder: (context, state) => const DeliveryListScreen(),
          ),
          GoRoute(
            path: '/operations',
            builder: (context, state) => const OperationsScreen(),
          ),
        ],
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            dashboardFutureProvider.overrideWith((ref) async => mockDashboard),
            receiptsFutureProvider.overrideWith((ref) async => []),
            deliveriesFutureProvider.overrideWith((ref) async => []),
            authProvider.overrideWith(() => MockAuthNotifier(
              initialUser: const AuthUser(id: 1, name: 'Warehouse Operator', email: 'op@stocksense.com', role: 'WAREHOUSE_STAFF'),
            )),
          ],
          child: MaterialApp.router(routerConfig: router),
        ),
      );

      await tester.pumpAndSettle();

      // Verify we are on Dashboard
      expect(find.text('Deliveries'), findsOneWidget);

      // Tap Deliveries hero card
      await tester.tap(find.text('Deliveries'));
      await tester.pumpAndSettle();

      // VERIFY: We are on Outbound Deliveries screen, NOT OperationsScreen / Operator Dashboard
      expect(find.text('Outbound Deliveries'), findsOneWidget);
      expect(find.byType(DeliveryListScreen), findsOneWidget);
      expect(find.byType(OperationsScreen), findsNothing);
    });

    testWidgets('3. Home -> Operator Dashboard button explicitly opens Operator Dashboard', (tester) async {
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final router = GoRouter(
        initialLocation: '/home',
        routes: [
          GoRoute(
            path: '/home',
            builder: (context, state) => const DashboardScreen(),
          ),
          GoRoute(
            path: '/operations',
            builder: (context, state) => const OperationsScreen(),
          ),
        ],
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            dashboardFutureProvider.overrideWith((ref) async => mockDashboard),
            receiptsFutureProvider.overrideWith((ref) async => []),
            deliveriesFutureProvider.overrideWith((ref) async => []),
            transfersFutureProvider.overrideWith((ref) async => []),
            adjustmentsFutureProvider.overrideWith((ref) async => []),
            authProvider.overrideWith(() => MockAuthNotifier(
              initialUser: const AuthUser(id: 1, name: 'Warehouse Operator', email: 'op@stocksense.com', role: 'WAREHOUSE_STAFF'),
            )),
          ],
          child: MaterialApp.router(routerConfig: router),
        ),
      );

      await tester.pumpAndSettle();

      // Find the explicit Operator Dashboard button
      final dashboardButton = find.text('Operator Dashboard');
      expect(dashboardButton, findsOneWidget);

      await tester.tap(dashboardButton);
      await tester.pumpAndSettle();

      // VERIFY: We are on OperationsScreen / Operator Dashboard
      expect(find.byType(OperationsScreen), findsOneWidget);
    });

    testWidgets('4. Back navigation from Receipt screen returns to Home', (tester) async {
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final router = GoRouter(
        initialLocation: '/home',
        routes: [
          GoRoute(
            path: '/home',
            builder: (context, state) => const DashboardScreen(),
          ),
          GoRoute(
            path: '/receipts',
            builder: (context, state) => const ReceiptListScreen(),
          ),
        ],
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            dashboardFutureProvider.overrideWith((ref) async => mockDashboard),
            receiptsFutureProvider.overrideWith((ref) async => []),
            authProvider.overrideWith(() => MockAuthNotifier(
              initialUser: const AuthUser(id: 1, name: 'Warehouse Operator', email: 'op@stocksense.com', role: 'WAREHOUSE_STAFF'),
            )),
          ],
          child: MaterialApp.router(routerConfig: router),
        ),
      );

      await tester.pumpAndSettle();

      // Push Receipt screen
      await tester.tap(find.text('Receipts'));
      await tester.pumpAndSettle();
      expect(find.byType(ReceiptListScreen), findsOneWidget);

      // Tap Back button
      final backButton = find.byType(BackButton);
      expect(backButton, findsOneWidget);
      await tester.tap(backButton);
      await tester.pumpAndSettle();

      // VERIFY: Returned to Home / DashboardScreen
      expect(find.byType(DashboardScreen), findsOneWidget);
      expect(find.byType(ReceiptListScreen), findsNothing);
    });

    testWidgets('5. Back navigation from Delivery screen returns to Home', (tester) async {
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final router = GoRouter(
        initialLocation: '/home',
        routes: [
          GoRoute(
            path: '/home',
            builder: (context, state) => const DashboardScreen(),
          ),
          GoRoute(
            path: '/deliveries',
            builder: (context, state) => const DeliveryListScreen(),
          ),
        ],
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            dashboardFutureProvider.overrideWith((ref) async => mockDashboard),
            deliveriesFutureProvider.overrideWith((ref) async => []),
            authProvider.overrideWith(() => MockAuthNotifier(
              initialUser: const AuthUser(id: 1, name: 'Warehouse Operator', email: 'op@stocksense.com', role: 'WAREHOUSE_STAFF'),
            )),
          ],
          child: MaterialApp.router(routerConfig: router),
        ),
      );

      await tester.pumpAndSettle();

      // Push Delivery screen
      await tester.tap(find.text('Deliveries'));
      await tester.pumpAndSettle();
      expect(find.byType(DeliveryListScreen), findsOneWidget);

      // Tap Back button
      final backButton = find.byType(BackButton);
      expect(backButton, findsOneWidget);
      await tester.tap(backButton);
      await tester.pumpAndSettle();

      // VERIFY: Returned to Home / DashboardScreen
      expect(find.byType(DashboardScreen), findsOneWidget);
      expect(find.byType(DeliveryListScreen), findsNothing);
    });

    testWidgets('6. Operations KPI Pending Receipts routes to ReceiptListScreen', (tester) async {
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final router = GoRouter(
        initialLocation: '/home',
        routes: [
          GoRoute(
            path: '/home',
            builder: (context, state) => const DashboardScreen(),
          ),
          GoRoute(
            path: '/receipts',
            builder: (context, state) => const ReceiptListScreen(),
          ),
        ],
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            dashboardFutureProvider.overrideWith((ref) async => mockDashboard),
            receiptsFutureProvider.overrideWith((ref) async => []),
            authProvider.overrideWith(() => MockAuthNotifier(
              initialUser: const AuthUser(id: 1, name: 'Warehouse Staff', email: 'staff@stocksense.com', role: 'WAREHOUSE_STAFF'),
            )),
          ],
          child: MaterialApp.router(routerConfig: router),
        ),
      );

      await tester.pumpAndSettle();

      // Find Pending Receipts tile
      final pendingReceiptsTile = find.text('Pending Receipts');
      expect(pendingReceiptsTile, findsOneWidget);

      await tester.tap(pendingReceiptsTile);
      await tester.pumpAndSettle();

      expect(find.byType(ReceiptListScreen), findsOneWidget);
    });

    testWidgets('7. Operations KPI Transfers Scheduled routes to TransferListScreen', (tester) async {
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final router = GoRouter(
        initialLocation: '/home',
        routes: [
          GoRoute(
            path: '/home',
            builder: (context, state) => const DashboardScreen(),
          ),
          GoRoute(
            path: '/transfers',
            builder: (context, state) => const TransferListScreen(),
          ),
        ],
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            dashboardFutureProvider.overrideWith((ref) async => mockDashboard),
            transfersFutureProvider.overrideWith((ref) async => []),
            authProvider.overrideWith(() => MockAuthNotifier(
              initialUser: const AuthUser(id: 1, name: 'Warehouse Staff', email: 'staff@stocksense.com', role: 'WAREHOUSE_STAFF'),
            )),
          ],
          child: MaterialApp.router(routerConfig: router),
        ),
      );

      await tester.pumpAndSettle();

      final transfersTile = find.text('Transfers Scheduled');
      expect(transfersTile, findsOneWidget);

      await tester.tap(transfersTile);
      await tester.pumpAndSettle();

      expect(find.byType(TransferListScreen), findsOneWidget);
    });

    testWidgets('8. Recent Movements: View All routes to HistoryScreen', (tester) async {
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final router = GoRouter(
        initialLocation: '/home',
        routes: [
          GoRoute(
            path: '/home',
            builder: (context, state) => const DashboardScreen(),
          ),
          GoRoute(
            path: '/history',
            builder: (context, state) => const HistoryScreen(),
          ),
        ],
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            dashboardFutureProvider.overrideWith((ref) async => mockDashboard),
            ledgerFutureProvider.overrideWith((ref) async => []),
            moveHistoryFutureProvider.overrideWith((ref) async => []),
            authProvider.overrideWith(() => MockAuthNotifier(
              initialUser: const AuthUser(id: 1, name: 'Warehouse Staff', email: 'staff@stocksense.com', role: 'WAREHOUSE_STAFF'),
            )),
          ],
          child: MaterialApp.router(routerConfig: router),
        ),
      );

      await tester.pumpAndSettle();

      final viewAllButtons = find.text('View All');
      // The second View All is for Recent Movements
      await tester.tap(viewAllButtons.last);
      await tester.pumpAndSettle();

      expect(find.byType(HistoryScreen), findsOneWidget);
    });

    testWidgets('9. Recent Movements: Tapping a RECEIPT move opens ReceiptListScreen', (tester) async {
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final router = GoRouter(
        initialLocation: '/home',
        routes: [
          GoRoute(
            path: '/home',
            builder: (context, state) => const DashboardScreen(),
          ),
          GoRoute(
            path: '/receipts',
            builder: (context, state) => const ReceiptListScreen(),
          ),
        ],
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            dashboardFutureProvider.overrideWith((ref) async => mockDashboard),
            receiptsFutureProvider.overrideWith((ref) async => []),
            authProvider.overrideWith(() => MockAuthNotifier(
              initialUser: const AuthUser(id: 1, name: 'Warehouse Staff', email: 'staff@stocksense.com', role: 'WAREHOUSE_STAFF'),
            )),
          ],
          child: MaterialApp.router(routerConfig: router),
        ),
      );

      await tester.pumpAndSettle();

      // Tap WH/IN/0001 (RECEIPT)
      final receiptMove = find.text('WH/IN/0001');
      expect(receiptMove, findsOneWidget);

      await tester.tap(receiptMove);
      await tester.pumpAndSettle();

      expect(find.byType(ReceiptListScreen), findsOneWidget);
    });

    testWidgets('10. Role-based access logic: role determines permissions, feature determines destination', (tester) async {
      // Operator user
      const operatorUser = AuthUser(
        id: 1,
        name: 'Warehouse Operator',
        email: 'operator@stocksense.com',
        role: 'WAREHOUSE_STAFF',
      );

      expect(operatorUser.isStaff, isTrue);
      expect(operatorUser.isManager, isFalse);
      expect(operatorUser.hasPermission('create_receipt'), isTrue);
      expect(operatorUser.hasPermission('validate_receipt'), isTrue);
      expect(operatorUser.hasPermission('validate_adjustment'), isFalse);

      // Manager user
      const managerUser = AuthUser(
        id: 2,
        name: 'Inventory Manager',
        email: 'manager@stocksense.com',
        role: 'INVENTORY_MANAGER',
      );

      expect(managerUser.isManager, isTrue);
      expect(managerUser.isStaff, isFalse);
      expect(managerUser.hasPermission('create_receipt'), isTrue);
      expect(managerUser.hasPermission('validate_receipt'), isTrue);
      expect(managerUser.hasPermission('validate_adjustment'), isTrue);
    });
  });
}
