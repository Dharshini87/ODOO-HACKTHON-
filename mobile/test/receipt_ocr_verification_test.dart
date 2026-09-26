import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:stocksense_mobile/features/receipts/presentation/physical_receipt_verification_card.dart';

import 'package:stocksense_mobile/features/receipts/presentation/receipt_detail_screen.dart';
import 'package:stocksense_mobile/shared/providers/inventory_providers.dart';

class MockReceiptsRepository implements ReceiptsRepository {
  final ReceiptVerificationResult? mockVerification;
  final ReceiptDocumentMeta? mockDocument;

  MockReceiptsRepository({this.mockVerification, this.mockDocument});

  @override
  Future<ReceiptVerificationResult?> getReceiptVerification(int id) async => mockVerification;

  @override
  Future<ReceiptDocumentMeta?> getReceiptDocument(int id) async => mockDocument;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  group('OCR Physical Receipt Verification Domain Models', () {
    test('ReceiptVerificationResult correctly parses MATCH payload', () {
      final json = {
        'status': 'MATCH',
        'confidence': 0.96,
        'supplier': {
          'status': 'MATCH',
          'system': 'ABC Steel Industries',
          'ocr': 'ABC Steel Industries Pvt Ltd',
        },
        'receipt_number': {
          'status': 'MATCH',
          'system': 'INV-2026-00123',
          'ocr': 'INV-2026-00123',
        },
        'receipt_date': '2026-09-26',
        'items': [
          {
            'product_id': 12,
            'status': 'MATCH',
            'system_quantity': 100.0,
            'ocr_quantity': 100.0,
            'difference': 0.0,
            'unit': 'kg',
          }
        ],
        'issues': [],
      };

      final result = ReceiptVerificationResult.fromJson(json);
      expect(result.status, 'MATCH');
      expect(result.isMatch, isTrue);
      expect(result.isReviewRequired, isFalse);
      expect(result.confidence, 0.96);
      expect(result.supplierSystem, 'ABC Steel Industries');
      expect(result.items.first.systemQuantity, 100.0);
      expect(result.items.first.ocrQuantity, 100.0);
      expect(result.items.first.difference, 0.0);
      expect(result.issues, isEmpty);
    });

    test('ReceiptVerificationResult correctly parses MISMATCH / REVIEW_REQUIRED payload (Section 60)', () {
      final json = {
        'status': 'REVIEW_REQUIRED',
        'confidence': 0.91,
        'supplier': {
          'status': 'MATCH',
          'system': 'ABC Steel Industries',
          'ocr': 'ABC Steel Industries',
        },
        'receipt_number': {
          'status': 'MATCH',
          'system': 'INV-2026-001',
          'ocr': 'INV-2026-001',
        },
        'items': [
          {
            'product_id': 12,
            'status': 'MISMATCH',
            'system_quantity': 100.0,
            'ocr_quantity': 95.0,
            'difference': -5.0,
            'unit': 'kg',
          }
        ],
        'issues': [
          'Quantity mismatch for Steel Rod: Digital receipt expects 100.0 kg, physical document shows 95.0 kg (Difference: -5.0 kg)'
        ],
      };

      final result = ReceiptVerificationResult.fromJson(json);
      expect(result.status, 'REVIEW_REQUIRED');
      expect(result.isReviewRequired, isTrue);
      expect(result.isMatch, isFalse);
      expect(result.confidence, 0.91);
      expect(result.items.first.status, 'MISMATCH');
      expect(result.items.first.systemQuantity, 100.0);
      expect(result.items.first.ocrQuantity, 95.0);
      expect(result.items.first.difference, -5.0);
      expect(result.issues.length, 1);
      expect(result.issues.first, contains('Difference: -5.0 kg'));
    });
  });

  group('PhysicalReceiptVerificationCard Widget Tests', () {
    testWidgets('Renders upload prompt and security disclaimer initially', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            receiptsRepositoryProvider.overrideWithValue(MockReceiptsRepository()),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: PhysicalReceiptVerificationCard(
                  receiptId: 42,
                  reference: 'RCPT-20260926-001',
                  productName: 'Steel Rod',
                  quantity: 100.0,
                  supplier: 'ABC Steel Industries',
                ),
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Verify title & subtitle
      expect(find.text('Physical Receipt Verification'), findsOneWidget);
      expect(find.text('Upload Physical Receipt (PDF or Image)'), findsOneWidget);
      expect(find.text('Upload & Verify Receipt'), findsOneWidget);

      // Verify mandatory architectural safety disclaimer
      expect(
        find.text(
          'OCR is an assistive verification layer only. Inventory is modified only upon official Receipt Validation.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('ReceiptDetailScreen embeds PhysicalReceiptVerificationCard', (tester) async {
      final receipt = StockMoveItem(
        id: 10,
        reference: 'RCPT-TEST-001',
        moveType: 'RECEIPT',
        status: 'READY',
        productId: 1,
        productName: 'Steel Rod',
        sku: 'SR-001',
        quantity: 100.0,
        fromLocationId: 0,
        fromLocationName: 'Vendor',
        toLocationId: 1,
        toLocationName: 'Rack A',
        contact: 'ABC Steel Industries',
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            receiptsRepositoryProvider.overrideWithValue(MockReceiptsRepository()),
          ],
          child: MaterialApp(
            home: ReceiptDetailScreen(initialReceipt: receipt),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Check header and item
      expect(find.text('RCPT-TEST-001'), findsOneWidget);
      expect(find.text('Physical Receipt Verification'), findsOneWidget);
      expect(find.text('Confirm Receiving Goods'), findsOneWidget);
    });
  });
}

