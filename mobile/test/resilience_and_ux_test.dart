import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:stocksense_mobile/core/errors/app_exception.dart';
import 'package:stocksense_mobile/core/widgets/error_view.dart';
import 'package:stocksense_mobile/core/widgets/status_badge.dart';
import 'package:stocksense_mobile/core/widgets/system_feedback.dart';
import 'package:stocksense_mobile/shared/providers/inventory_providers.dart';
import 'package:stocksense_mobile/features/stock/presentation/stock_screen.dart';
import 'package:stocksense_mobile/features/deliveries/presentation/delivery_detail_screen.dart';

void main() {
  group('Section 31: Stock Mobile UI Tests', () {
    final sampleStockItem = StockItem(
      productId: 1,
      productName: 'Steel Rod',
      sku: 'SR-001',
      costPerUnit: 45.0,
      onHand: 100.0,
      reserved: 20.0,
      freeToUse: 80.0,
      reorderPoint: 15.0,
      lowStock: false,
      warehouseName: 'Main Warehouse',
      locationName: 'Rack A',
      unitOfMeasure: 'kg',
    );

    testWidgets('Stock Card displays all Section 31 mandatory fields and visual arithmetic formula', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            stockFutureProvider.overrideWith((ref) async => [sampleStockItem]),
            productsFutureProvider.overrideWith((ref) async => []),
          ],
          child: const MaterialApp(
            home: StockScreen(),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Product and SKU
      expect(find.text('Steel Rod'), findsOneWidget);
      expect(find.text('SR-001'), findsOneWidget);

      // Warehouse and Location
      expect(find.text('Main Warehouse'), findsOneWidget);
      expect(find.text('Rack A'), findsOneWidget);

      // Inventory Metrics with unit of measure
      expect(find.text('100 kg'), findsOneWidget); // On Hand
      expect(find.text('20 kg'), findsOneWidget);  // Reserved
      expect(find.text('80 kg'), findsOneWidget);  // Free to Use

      // Inventory Status
      expect(find.text('NORMAL'), findsOneWidget);

      // Visually Obvious Relationship: ON HAND - RESERVED = FREE TO USE
      expect(find.text('ON HAND'), findsOneWidget);
      expect(find.text('RESERVED'), findsOneWidget);
      expect(find.text('FREE TO USE'), findsOneWidget);
      expect(find.text('ON HAND  -  RESERVED  =  FREE TO USE'), findsOneWidget);
    });
  });

  group('Section 32: Delivery Mobile UI Tests', () {
    testWidgets('Available Stock delivery shows Requested, Free to Use, ✓ Available, and READY', (tester) async {
      final readyDelivery = StockMoveItem(
        id: 10,
        reference: 'WH/OUT/0010',
        moveType: 'delivery',
        productId: 1,
        productName: 'Steel Rod',
        sku: 'SR-001',
        fromLocationId: 1,
        fromLocationName: 'Main Warehouse',
        toLocationId: 2,
        toLocationName: 'Customer A',
        quantity: 20.0,
        status: 'ready',
        onHand: 100.0,
        reserved: 20.0,
        freeToUse: 80.0,
        requested: 20.0,
        shortage: 0.0,
      );

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: DeliveryDetailScreen(initialDelivery: readyDelivery),
          ),
        ),
      );

      expect(find.text('Steel Rod'), findsOneWidget);
      expect(find.text('20 kg'), findsWidgets); // Requested
      expect(find.text('80 kg'), findsWidgets); // Free to Use
      expect(find.text('✓ Available'), findsOneWidget);
      expect(find.text('READY'), findsWidgets);
    });

    testWidgets('Insufficient Stock delivery shows Requested, Free to Use, Shortage, ⚠ Insufficient Available Stock, and WAITING', (tester) async {
      final waitingDelivery = StockMoveItem(
        id: 11,
        reference: 'WH/OUT/0011',
        moveType: 'delivery',
        productId: 1,
        productName: 'Steel Rod',
        sku: 'SR-001',
        fromLocationId: 1,
        fromLocationName: 'Main Warehouse',
        toLocationId: 2,
        toLocationName: 'Customer B',
        quantity: 20.0,
        status: 'waiting',
        onHand: 10.0,
        reserved: 5.0,
        freeToUse: 5.0,
        requested: 20.0,
        shortage: 15.0,
        isWaitingForStock: true,
      );

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: DeliveryDetailScreen(initialDelivery: waitingDelivery),
          ),
        ),
      );

      expect(find.text('Steel Rod'), findsOneWidget);
      expect(find.text('20 kg'), findsWidgets); // Requested
      expect(find.text('5 kg'), findsWidgets);  // Free to Use
      expect(find.text('15 kg'), findsWidgets); // Shortage
      expect(find.text('⚠ Insufficient Available Stock'), findsOneWidget);
      expect(find.text('WAITING'), findsWidgets);
    });

    testWidgets('Done delivery shows DONE badge after validation', (tester) async {
      final doneDelivery = StockMoveItem(
        id: 12,
        reference: 'WH/OUT/0012',
        moveType: 'delivery',
        productId: 1,
        productName: 'Steel Rod',
        sku: 'SR-001',
        fromLocationId: 1,
        fromLocationName: 'Main Warehouse',
        toLocationId: 2,
        toLocationName: 'Customer C',
        quantity: 20.0,
        status: 'done',
        onHand: 80.0,
        reserved: 0.0,
        freeToUse: 80.0,
        requested: 20.0,
        shortage: 0.0,
      );

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: DeliveryDetailScreen(initialDelivery: doneDelivery),
          ),
        ),
      );

      expect(find.text('DONE'), findsWidgets);
    });
  });

  group('Section 33: Mobile Status Colors Tests', () {
    testWidgets('Always shows explicit text and never relies on color alone', (tester) async {
      final testStatuses = [
        'DRAFT',
        'WAITING',
        'READY',
        'DONE',
        'CANCELED',
        'NORMAL',
        'LOW STOCK',
        'OUT OF STOCK',
      ];

      for (final s in testStatuses) {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: StatusBadge(status: s),
            ),
          ),
        );
        expect(find.text(s), findsOneWidget);
      }
    });
  });

  group('Section 35 & 36: Error Handling and Offline Behavior Tests', () {
    test('Exceptions map correctly for 401, 403, 404, 409, 422, 500', () {
      final unauth = UnauthorizedException();
      expect(unauth.statusCode, 401);
      expect(unauth.title, 'Unauthorized');

      final forbidden = ForbiddenException();
      expect(forbidden.statusCode, 403);
      expect(forbidden.title, 'Forbidden');

      final notFound = NotFoundException();
      expect(notFound.statusCode, 404);
      expect(notFound.title, 'Not Found');

      final conflict = ConflictException();
      expect(conflict.statusCode, 409);
      expect(conflict.title, 'Conflict');

      final validation = ValidationException();
      expect(validation.statusCode, 422);
      expect(validation.title, 'Validation Error');

      final server = ServerException();
      expect(server.statusCode, 500);
      expect(server.title, 'Server Error');
    });

    test('Section 36 OfflineException contains required title and message', () {
      final offline = OfflineException();
      expect(offline.title, 'No Internet Connection');
      expect(offline.message, 'Inventory changes require a connection.');
    });

    testWidgets('ErrorView renders custom title, message, and Retry button', (tester) async {
      bool retried = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ErrorView(
              title: 'No Internet Connection',
              message: 'Inventory changes require a connection.',
              onRetry: () => retried = true,
            ),
          ),
        ),
      );

      expect(find.text('No Internet Connection'), findsOneWidget);
      expect(find.text('Inventory changes require a connection.'), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);

      await tester.tap(find.text('Retry'));
      expect(retried, isTrue);
    });

    testWidgets('InsufficientStockCard renders shortage and warning banner', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: InsufficientStockCard(
              productName: 'Steel Rod',
              requested: 20,
              freeToUse: 5,
              shortage: 15,
            ),
          ),
        ),
      );

      expect(find.text('Steel Rod'), findsOneWidget);
      expect(find.text('Requested:\n20 kg'), findsOneWidget);
      expect(find.text('Free to Use:\n5 kg'), findsOneWidget);
      expect(find.text('Shortage:\n15 kg'), findsOneWidget);
      expect(find.text('⚠ Insufficient Available Stock'), findsOneWidget);
      expect(find.text('WAITING'), findsOneWidget);
    });
  });
}
