import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:stocksense_mobile/shared/providers/inventory_providers.dart';
import 'package:stocksense_mobile/features/move_history/presentation/history_screen.dart';

void main() {
  group('Section 24: STOCK LEDGER Model & Serialization', () {
    test('StockLedgerItem deserializes all Section 24 mandatory fields', () {
      final json = {
        'id': 42,
        'transaction_id': 10,
        'product_id': 1,
        'product_name': 'Steel Rod',
        'sku': 'SR-100',
        'location_id': 2,
        'location_name': 'Rack A',
        'warehouse_name': 'Main Warehouse',
        'quantity_before': 80.0,
        'quantity_change': -3.0,
        'quantity_after': 77.0,
        'movement_type': 'ADJUSTMENT',
        'reference': 'ADJ-0001',
        'created_at': '2026-09-26T12:00:00',
      };

      final item = StockLedgerItem.fromJson(json);

      expect(item.id, 42);
      expect(item.transactionId, 10);
      expect(item.productId, 1);
      expect(item.productName, 'Steel Rod');
      expect(item.sku, 'SR-100');
      expect(item.locationId, 2);
      expect(item.locationName, 'Rack A');
      expect(item.warehouseName, 'Main Warehouse');
      expect(item.quantityBefore, 80.0);
      expect(item.quantityChange, -3.0);
      expect(item.quantityAfter, 77.0);
      expect(item.movementType, 'ADJUSTMENT');
      expect(item.reference, 'ADJ-0001');
      expect(item.createdAt, '2026-09-26T12:00:00');
    });

    test('StockLedgerItem handles all 5 movement types correctly', () {
      final types = ['RECEIPT', 'DELIVERY', 'TRANSFER_IN', 'TRANSFER_OUT', 'ADJUSTMENT'];
      for (final type in types) {
        final item = StockLedgerItem.fromJson({
          'id': 1,
          'product_id': 1,
          'location_id': 1,
          'quantity_before': 100.0,
          'quantity_change': 20.0,
          'quantity_after': 120.0,
          'movement_type': type,
          'created_at': '2026-09-26T10:00:00',
        });
        expect(item.movementType, type);
      }
    });
  });

  group('Section 25: MOVE HISTORY Derived Model & Serialization', () {
    test('StockMoveItem deserializes derived fields without separate moves table', () {
      final json = {
        'id': 101,
        'reference': 'DEL-2026-001',
        'type': 'DELIVERY',
        'date': '2026-09-26T14:30:00',
        'contact': 'Acme Construction',
        'from_location': 'Main Warehouse / Rack B',
        'from_location_id': 2,
        'to_location': 'Customer Jobsite',
        'to_location_id': 0,
        'product_id': 1,
        'product_name': 'Steel Rod',
        'sku': 'SR-100',
        'quantity': 25.0,
        'status': 'DONE',
        'created_at': '2026-09-26T14:30:00',
      };

      final move = StockMoveItem.fromJson(json);

      expect(move.id, 101);
      expect(move.reference, 'DEL-2026-001');
      expect(move.moveType, 'DELIVERY');
      expect(move.contact, 'Acme Construction');
      expect(move.fromLocationName, 'Main Warehouse / Rack B');
      expect(move.toLocationName, 'Customer Jobsite');
      expect(move.quantity, 25.0);
      expect(move.status, 'done');
      expect(move.sku, 'SR-100');
      expect(move.productName, 'Steel Rod');
    });
  });

  group('Section 24 & 25 UI Widget Tests', () {
    final mockMoves = [
      StockMoveItem(
        id: 1,
        reference: 'REC-001',
        moveType: 'RECEIPT',
        productId: 1,
        productName: 'Steel Rod',
        sku: 'SR-100',
        fromLocationId: 0,
        fromLocationName: 'Steel Corp Supplier',
        toLocationId: 1,
        toLocationName: 'Rack A',
        quantity: 100.0,
        status: 'done',
        contact: 'Steel Corp Inc',
        date: '2026-09-26T10:00:00',
      ),
      StockMoveItem(
        id: 2,
        reference: 'DEL-002',
        moveType: 'DELIVERY',
        productId: 1,
        productName: 'Steel Rod',
        sku: 'SR-100',
        fromLocationId: 1,
        fromLocationName: 'Rack A',
        toLocationId: 0,
        toLocationName: 'Customer Site B',
        quantity: 20.0,
        status: 'waiting',
        contact: 'Metro Builders Inc',
        date: '2026-09-26T11:00:00',
      ),
      StockMoveItem(
        id: 3,
        reference: 'TRF-003',
        moveType: 'TRANSFER',
        productId: 2,
        productName: 'Cement Bag',
        sku: 'CB-50',
        fromLocationId: 1,
        fromLocationName: 'Rack A',
        toLocationId: 2,
        toLocationName: 'Floor B',
        quantity: 15.0,
        status: 'ready',
        contact: 'Internal Logistics',
        date: '2026-09-26T12:00:00',
      ),
    ];

    final mockLedger = [
      StockLedgerItem(
        id: 101,
        transactionId: 1,
        productId: 1,
        productName: 'Steel Rod',
        sku: 'SR-100',
        locationId: 1,
        locationName: 'Rack A',
        warehouseName: 'Main Warehouse',
        quantityBefore: 0.0,
        quantityChange: 100.0,
        quantityAfter: 100.0,
        movementType: 'RECEIPT',
        reference: 'REC-001',
        createdAt: '2026-09-26T10:00:00',
      ),
      StockLedgerItem(
        id: 102,
        transactionId: 2,
        productId: 1,
        productName: 'Steel Rod',
        sku: 'SR-100',
        locationId: 1,
        locationName: 'Rack A',
        warehouseName: 'Main Warehouse',
        quantityBefore: 100.0,
        quantityChange: -20.0,
        quantityAfter: 80.0,
        movementType: 'DELIVERY',
        reference: 'DEL-002',
        createdAt: '2026-09-26T11:00:00',
      ),
      StockLedgerItem(
        id: 103,
        transactionId: 3,
        productId: 1,
        productName: 'Steel Rod',
        sku: 'SR-100',
        locationId: 1,
        locationName: 'Rack A',
        warehouseName: 'Main Warehouse',
        quantityBefore: 80.0,
        quantityChange: -3.0,
        quantityAfter: 77.0,
        movementType: 'ADJUSTMENT',
        reference: 'ADJ-001',
        createdAt: '2026-09-26T12:00:00',
      ),
    ];

    testWidgets('Section 25: Renders Move History List View with all required fields', (tester) async {
      tester.view.physicalSize = const Size(1200, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            moveHistoryFutureProvider.overrideWith((ref) => Future.value(mockMoves)),
            ledgerFutureProvider.overrideWith((ref) => Future.value(mockLedger)),
          ],
          child: const MaterialApp(
            home: HistoryScreen(),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Verify Reference
      expect(find.text('REC-001'), findsOneWidget);
      expect(find.text('DEL-002'), findsOneWidget);
      expect(find.text('TRF-003'), findsOneWidget);

      // Verify Contact
      expect(find.text('Steel Corp Inc'), findsOneWidget);
      expect(find.text('Metro Builders Inc'), findsOneWidget);

      // Verify From & To
      expect(find.text('Steel Corp Supplier'), findsOneWidget);
      expect(find.text('Customer Site B'), findsOneWidget);
      expect(find.text('Rack A'), findsWidgets);

      // Verify Quantity
      expect(find.text('+100 kg'), findsOneWidget);
      expect(find.text('-20 kg'), findsOneWidget);

      // Verify Status Badges
      expect(find.text('DONE'), findsOneWidget);
      expect(find.text('WAITING'), findsOneWidget);
      expect(find.text('READY'), findsOneWidget);
    });

    testWidgets('Section 25: Search filters by Reference, Contact, and SKU', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            moveHistoryFutureProvider.overrideWith((ref) => Future.value(mockMoves)),
            ledgerFutureProvider.overrideWith((ref) => Future.value(mockLedger)),
          ],
          child: const MaterialApp(
            home: HistoryScreen(),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Search by SKU: CB-50
      final searchField = find.byType(TextField).first;
      await tester.enterText(searchField, 'CB-50');
      await tester.pumpAndSettle();

      expect(find.text('TRF-003'), findsOneWidget);
      expect(find.text('REC-001'), findsNothing);
      expect(find.text('DEL-002'), findsNothing);

      // Search by Contact: Steel Corp
      await tester.enterText(searchField, 'Steel Corp');
      await tester.pumpAndSettle();

      expect(find.text('REC-001'), findsOneWidget);
      expect(find.text('TRF-003'), findsNothing);
    });

    testWidgets('Section 25: Secondary Kanban view renders status columns', (tester) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            moveHistoryFutureProvider.overrideWith((ref) => Future.value(mockMoves)),
            ledgerFutureProvider.overrideWith((ref) => Future.value(mockLedger)),
          ],
          child: const MaterialApp(
            home: HistoryScreen(),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Switch to Kanban tab (Index 1)
      await tester.tap(find.text('Moves (Kanban)'));
      await tester.pumpAndSettle();

      // Assert columns are present
      expect(find.text('Draft'), findsOneWidget);
      expect(find.text('Waiting'), findsOneWidget);
      expect(find.text('Ready'), findsOneWidget);
      expect(find.text('Done'), findsOneWidget);

      // In Done column: REC-001
      expect(find.text('REC-001'), findsOneWidget);
    });

    testWidgets('Section 24: Stock Ledger renders as a Vertical Timeline with arithmetic delta', (tester) async {
      tester.view.physicalSize = const Size(1200, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            moveHistoryFutureProvider.overrideWith((ref) => Future.value(mockMoves)),
            ledgerFutureProvider.overrideWith((ref) => Future.value(mockLedger)),
          ],
          child: const MaterialApp(
            home: HistoryScreen(),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Switch to Stock Ledger tab (Index 2)
      await tester.tap(find.text('Stock Ledger'));
      await tester.pumpAndSettle();

      // Assert Section 24 arithmetic delta labels (BEFORE -> CHANGE -> AFTER)
      expect(find.text('BEFORE'), findsWidgets);
      expect(find.text('CHANGE'), findsWidgets);
      expect(find.text('AFTER'), findsWidgets);

      // Check values for Adjustment (80.0 kg -> -3.0 kg -> 77.0 kg)
      expect(find.text('80.0 kg'), findsWidgets);
      expect(find.text('-3.0 kg'), findsOneWidget);
      expect(find.text('77.0 kg'), findsOneWidget);

      // Check movement types
      expect(find.text('RECEIPT'), findsWidgets);
      expect(find.text('DELIVERY'), findsWidgets);
      expect(find.text('ADJUSTMENT'), findsWidgets);

      // Check Section 24 Immutable tag and audit statement
      expect(find.text('#101'), findsOneWidget);
      expect(find.text('#102'), findsOneWidget);
      expect(find.text('#103'), findsOneWidget);
      expect(find.text('READ ONLY • APPEND ONLY • IMMUTABLE AUDIT TRAIL'), findsWidgets);
    });
  });
}
