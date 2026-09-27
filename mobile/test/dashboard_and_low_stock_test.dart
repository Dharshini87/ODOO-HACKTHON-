import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:stocksense_mobile/shared/providers/inventory_providers.dart';
import 'package:stocksense_mobile/features/auth/presentation/auth_provider.dart';
import 'package:stocksense_mobile/features/dashboard/presentation/dashboard_screen.dart';

void main() {
  group('Section 26 & 27 Dashboard and Low Stock Unit Tests', () {
    test('DashboardData parsing from database-driven JSON', () {
      final json = {
        'total_stock': 1250.0,
        'low_stock': 3,
        'out_of_stock': 1,
        'pending_receipts': 4,
        'pending_deliveries': 6,
        'waiting_deliveries': 2,
        'transfers_scheduled': 1,
        'total_products': 25,
        'low_stock_products': [
          {
            'product_id': 1,
            'product_name': 'Steel Rod',
            'sku': 'ROD-01',
            'on_hand': 0.0,
            'reserved': 0.0,
            'free_to_use': 0.0,
            'reorder_level': 20.0,
            'status': 'OUT OF STOCK',
          },
          {
            'product_id': 2,
            'product_name': 'Copper Wire',
            'sku': 'WIRE-02',
            'on_hand': 15.0,
            'reserved': 5.0,
            'free_to_use': 10.0,
            'reorder_level': 30.0,
            'status': 'LOW STOCK',
          },
        ],
        'recent_movements': [
          {
            'id': 10,
            'reference': 'WH/IN/0001',
            'type': 'RECEIPT',
            'status': 'DONE',
            'product_name': 'Steel Rod',
            'sku': 'ROD-01',
            'quantity': 100.0,
          },
        ],
        'intelligence_preview': {
          'total_stock_value': 45200.50,
          'fast_moving_items': ['Steel Rod', 'Copper Wire'],
          'dead_stock_count': 2,
          'reorder_recommended_count': 4,
        },
      };

      final data = DashboardData.fromJson(json);

      expect(data.totalStock, equals(1250.0));
      expect(data.lowStockCount, equals(3));
      expect(data.outOfStockCount, equals(1));
      expect(data.pendingReceipts, equals(4));
      expect(data.pendingDeliveries, equals(6));
      expect(data.waitingDeliveries, equals(2));
      expect(data.transfersScheduled, equals(1));
      expect(data.lowStockProducts.length, equals(2));
      expect(data.recentMovements.length, equals(1));
      expect(data.intelligence.totalStockValue, equals(45200.50));
      expect(data.intelligence.fastMovingItems, contains('Steel Rod'));
    });

    test('Section 27 Low Stock rules evaluated correctly', () {
      // Rule 1: if on_hand == 0 -> OUT OF STOCK
      final itemZero = StockItem(
        productId: 1,
        productName: 'Zero Item',
        sku: 'Z-01',
        costPerUnit: 10,
        onHand: 0,
        reserved: 0,
        freeToUse: 0,
        reorderPoint: 20,
        lowStock: true,
      );
      expect(itemZero.status, equals('OUT OF STOCK'));

      // Rule 2: elif on_hand <= reorder_level -> LOW STOCK
      final itemLow = StockItem(
        productId: 2,
        productName: 'Low Item',
        sku: 'L-02',
        costPerUnit: 10,
        onHand: 15,
        reserved: 0,
        freeToUse: 15,
        reorderPoint: 20,
        lowStock: true,
      );
      expect(itemLow.status, equals('LOW STOCK'));

      // Rule 3: else -> NORMAL
      final itemNormal = StockItem(
        productId: 3,
        productName: 'Normal Item',
        sku: 'N-03',
        costPerUnit: 10,
        onHand: 50,
        reserved: 5,
        freeToUse: 45,
        reorderPoint: 20,
        lowStock: false,
      );
      expect(itemNormal.status, equals('NORMAL'));
    });
  });

  group('Section 26 & 27 DashboardScreen Widget Tests', () {
    final mockDashboardData = DashboardData(
      totalStock: 3500.0,
      totalProducts: 40,
      lowStockCount: 2,
      outOfStockCount: 1,
      pendingReceipts: 3,
      pendingDeliveries: 5,
      waitingDeliveries: 2,
      transfersScheduled: 1,
      lowStockProducts: [
        LowStockItem(
          productId: 10,
          productName: 'Heavy Bolts',
          sku: 'BLT-01',
          onHand: 0.0,
          reserved: 0.0,
          freeToUse: 0.0,
          reorderLevel: 50.0,
          status: 'OUT OF STOCK',
        ),
        LowStockItem(
          productId: 20,
          productName: 'Copper Pipes',
          sku: 'COP-02',
          onHand: 25.0,
          reserved: 5.0,
          freeToUse: 20.0,
          reorderLevel: 40.0,
          status: 'LOW STOCK',
        ),
      ],
      recentMovements: [
        DashboardRecentMovement(
          id: 1,
          reference: 'WH/IN/0042',
          type: 'RECEIPT',
          status: 'DONE',
          productName: 'Heavy Bolts',
          sku: 'BLT-01',
          quantity: 200.0,
        ),
      ],
      intelligence: DashboardIntelligence(
        totalStockValue: 88500.00,
        fastMovingItems: ['Heavy Bolts'],
        deadStockCount: 1,
        reorderRecommendedCount: 3,
      ),
    );

    testWidgets('Renders all Section 26 metrics: Total Stock, Waiting Deliveries, Low Stock breakdown, and Intelligence for Manager', (tester) async {
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final managerUser = AuthUser(name: 'Manager User', email: 'manager@example.com', role: 'INVENTORY_MANAGER');

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authProvider.overrideWith(() => _MockAuthNotifier(managerUser)),
            dashboardFutureProvider.overrideWith((ref) async => mockDashboardData),
          ],
          child: const MaterialApp(
            home: DashboardScreen(),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Verify Total Stock card
      expect(find.text('TOTAL STOCK'), findsOneWidget);
      expect(find.text('3500'), findsOneWidget);

      // Verify Waiting Deliveries metric tile
      expect(find.text('Waiting Deliveries'), findsOneWidget);
      expect(find.text('2'), findsWidgets);

      // Verify Section 26 Low Stock Products section
      expect(find.text('Low Stock Products'), findsOneWidget);
      expect(find.text('Heavy Bolts'), findsWidgets);
      expect(find.text('Copper Pipes'), findsOneWidget);

      // Verify Section 27 Quantities display (ON HAND, RESERVED, FREE TO USE)
      expect(find.text('ON HAND'), findsWidgets);
      expect(find.text('RESERVED'), findsWidgets);
      expect(find.text('FREE TO USE'), findsWidgets);
      expect(find.text('OUT OF STOCK'), findsOneWidget);
      expect(find.text('LOW STOCK'), findsOneWidget);

      // Verify Section 26 Intelligence Preview (Manager only)
      expect(find.text('Inventory Intelligence'), findsOneWidget);
      expect(find.text('\$88500.00'), findsOneWidget);

      // Verify Recent Movements
      expect(find.text('Recent Movements'), findsOneWidget);
      expect(find.text('WH/IN/0042'), findsOneWidget);
    });

    testWidgets('Warehouse Staff sees core metrics but NOT Inventory Intelligence preview on Dashboard', (tester) async {
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final staffUser = AuthUser(name: 'Staff User', email: 'staff@example.com', role: 'WAREHOUSE_STAFF');

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authProvider.overrideWith(() => _MockAuthNotifier(staffUser)),
            dashboardFutureProvider.overrideWith((ref) async => mockDashboardData),
          ],
          child: const MaterialApp(
            home: DashboardScreen(),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Core metrics are visible
      expect(find.text('TOTAL STOCK'), findsOneWidget);
      expect(find.text('Low Stock Products'), findsOneWidget);
      expect(find.text('Recent Movements'), findsOneWidget);

      // Inventory Intelligence is NOT visible to staff
      expect(find.text('Inventory Intelligence'), findsNothing);
      expect(find.text('\$88500.00'), findsNothing);
    });
  });
}

class _MockAuthNotifier extends AuthNotifier {
  final AuthUser _mockUser;
  _MockAuthNotifier(this._mockUser);

  @override
  AuthState build() {
    return AuthState(
      isAuthenticated: true,
      user: _mockUser,
      isLoading: false,
    );
  }
}
