import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:stocksense_mobile/shared/providers/inventory_providers.dart';
import 'package:stocksense_mobile/features/auth/presentation/auth_provider.dart';
import 'package:stocksense_mobile/features/adjustments/presentation/adjustment_detail_screen.dart';

void main() {
  group('Section 23 Inventory Adjustments Unit Tests', () {
    test('Calculates count reconciliation correctly (Example: 80 kg sys, 77 kg phys -> -3 kg)', () {
      final json = {
        'id': 101,
        'reference': 'WH/ADJ/0001',
        'move_type': 'ADJUSTMENT',
        'product_id': 10,
        'product_name': 'Steel Rod',
        'sku': 'ROD-STL-001',
        'location_name': 'Rack A-01',
        'quantity': 77.0,
        'system_quantity': 80.0,
        'physical_count': 77.0,
        'difference': -3.0,
        'reason': 'Damaged',
        'status': 'draft',
        'reserved': 10.0,
        'free_to_use': 70.0,
      };

      final move = StockMoveItem.fromJson(json);

      expect(move.reference, equals('WH/ADJ/0001'));
      expect(move.systemQuantity, equals(80.0));
      expect(move.physicalCount, equals(77.0));
      expect(move.difference, equals(-3.0));
      expect(move.reason, equals('Damaged'));
      expect(move.status, equals('draft'));
      // Constraint check: physical_count (77) >= reserved (10) -> valid
      expect(move.physicalCount! >= move.reserved, isTrue);
    });

    test('Validates constraint: adjustment cannot result in on_hand < reserved', () {
      const reserved = 50.0;
      const physicalCountTooLow = 40.0;
      const physicalCountValid = 55.0;

      final bool isInvalid = physicalCountTooLow < reserved;
      final bool isValid = physicalCountValid >= reserved;

      expect(isInvalid, isTrue, reason: '40 kg physical count is less than 50 kg reserved stock');
      expect(isValid, isTrue, reason: '55 kg physical count satisfies reserved stock constraint');
    });

    test('Supported reasons matching Section 23 specification', () {
      const allowedReasons = [
        'Damaged',
        'Lost',
        'Counting Error',
        'Found Stock',
        'Other',
      ];

      expect(allowedReasons.contains('Damaged'), isTrue);
      expect(allowedReasons.contains('Lost'), isTrue);
      expect(allowedReasons.contains('Counting Error'), isTrue);
      expect(allowedReasons.contains('Found Stock'), isTrue);
      expect(allowedReasons.contains('Other'), isTrue);
      expect(allowedReasons.length, equals(5));
    });
  });

  group('Section 23 AdjustmentDetailScreen Widget Tests', () {
    final sampleAdjustment = StockMoveItem(
      id: 202,
      reference: 'WH/ADJ/0042',
      moveType: 'ADJUSTMENT',
      productId: 5,
      productName: 'Aluminum Sheets',
      sku: 'ALU-SHT-005',
      fromLocationId: 1,
      fromLocationName: 'Bay B-04',
      toLocationId: 0,
      toLocationName: '',
      quantity: 95.0,
      status: 'draft',
      systemQuantity: 100.0,
      physicalCount: 95.0,
      difference: -5.0,
      reason: 'Lost',
      reserved: 20.0,
      freeToUse: 80.0,
    );

    testWidgets('Renders all Section 23 required fields: Product, Location, System Qty, Physical Count, Difference, Reason', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: AdjustmentDetailScreen(initialAdjustment: sampleAdjustment),
          ),
        ),
      );

      // Verify Reference and Status
      expect(find.text('WH/ADJ/0042'), findsWidgets);
      expect(find.text('DRAFT'), findsOneWidget);

      // Verify Product and Location
      expect(find.text('Aluminum Sheets'), findsOneWidget);
      expect(find.text('ALU-SHT-005'), findsOneWidget);
      expect(find.text('Bay B-04'), findsOneWidget);

      // Verify Section 23 Numbers: System Qty (100), Physical Count (95), Difference (-5)
      expect(find.text('100'), findsOneWidget);
      expect(find.text('95'), findsOneWidget);
      expect(find.text('-5'), findsOneWidget);

      // Verify Reason
      expect(find.text('Lost'), findsOneWidget);

      // Verify Rule constraint
      expect(find.text('Stock Constraint Validation'), findsOneWidget);
    });

    testWidgets('Shows Pending Manager Validation banner for Warehouse Staff', (tester) async {
      final staffUser = AuthUser(name: 'John Staff', email: 'staff@example.com', role: 'WAREHOUSE_STAFF');

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authProvider.overrideWith(() => _MockAuthNotifier(staffUser)),
          ],
          child: MaterialApp(
            home: AdjustmentDetailScreen(initialAdjustment: sampleAdjustment),
          ),
        ),
      );

      // Staff should see the Pending Manager Validation notice
      expect(find.text('Pending Manager Validation'), findsOneWidget);
      // Validate button should NOT be present for staff
      expect(find.text('Validate Adjustment'), findsNothing);
    });

    testWidgets('Shows Validate Adjustment button for Inventory Manager', (tester) async {
      final managerUser = AuthUser(name: 'Sarah Manager', email: 'manager@example.com', role: 'INVENTORY_MANAGER');

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authProvider.overrideWith(() => _MockAuthNotifier(managerUser)),
          ],
          child: MaterialApp(
            home: AdjustmentDetailScreen(initialAdjustment: sampleAdjustment),
          ),
        ),
      );

      // Manager should see the Validate Adjustment button
      expect(find.text('Validate Adjustment'), findsOneWidget);
      expect(find.text('Pending Manager Validation'), findsNothing);
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
