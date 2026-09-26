import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:stocksense_mobile/shared/providers/inventory_providers.dart';
import 'package:stocksense_mobile/features/intelligence/presentation/intelligence_screen.dart';

void main() {
  group('Section 28 Inventory Intelligence Unit Tests', () {
    test('StockoutPredictionItem handles insufficient history according to specification', () {
      final jsonInsufficient = {
        'product_id': 1,
        'product_name': 'Titanium Fasteners',
        'sku': 'TIT-001',
        'current_stock': 50.0,
        'average_daily_usage': null,
        'reorder_level': 20.0,
        'estimated_days_to_reorder': null,
        'estimated_days_to_stockout': null,
        'has_sufficient_history': false,
        'message': 'Not enough historical movement data.',
      };

      final item = StockoutPredictionItem.fromJson(jsonInsufficient);

      expect(item.hasSufficientHistory, isFalse);
      expect(item.message, equals('Not enough historical movement data.'));
      expect(item.averageDailyUsage, isNull);
      expect(item.estimatedDaysToStockout, isNull);
      expect(item.estimatedDaysToReorder, isNull);
    });

    test('StockoutPredictionItem handles active consumption history with transparent velocity', () {
      final jsonActive = {
        'product_id': 2,
        'product_name': 'Steel Beams',
        'sku': 'STL-002',
        'current_stock': 80.0,
        'average_daily_usage': 20.0,
        'reorder_level': 20.0,
        'estimated_days_to_reorder': 3.0,
        'estimated_days_to_stockout': 4.0,
        'has_sufficient_history': true,
        'message': null,
      };

      final item = StockoutPredictionItem.fromJson(jsonActive);

      expect(item.hasSufficientHistory, isTrue);
      expect(item.currentStock, equals(80.0));
      expect(item.averageDailyUsage, equals(20.0));
      expect(item.estimatedDaysToStockout, equals(4.0));
      expect(item.estimatedDaysToReorder, equals(3.0));
    });

    test('ReorderRecommendationItem contains transparent explanation without ML fabrication', () {
      final jsonReorder = {
        'product_id': 2,
        'product_name': 'Steel Beams',
        'sku': 'STL-002',
        'current_stock': 80.0,
        'average_usage': 20.0,
        'target_coverage': 10,
        'recommended_reorder_quantity': 140.0,
        'explanation': 'Formula: Target Need = (Avg Usage: 20.0/day × Coverage: 10 days) + Buffer: 20 = 220. Deficit = 220 - Current Stock (80) = 140.0 units recommended.',
        'has_sufficient_history': true,
      };

      final item = ReorderRecommendationItem.fromJson(jsonReorder);

      expect(item.recommendedReorderQuantity, equals(140.0));
      expect(item.explanation, contains('Formula: Target Need'));
      expect(item.explanation, contains('Current Stock'));
      expect(item.targetCoverage, equals(10));
    });
  });

  group('Section 28 IntelligenceScreen Widget Tests', () {
    final mockStockoutList = [
      StockoutPredictionItem(
        productId: 1,
        productName: 'Titanium Fasteners',
        sku: 'TIT-001',
        currentStock: 50.0,
        reorderLevel: 20.0,
        hasSufficientHistory: false,
        message: 'Not enough historical movement data.',
      ),
      StockoutPredictionItem(
        productId: 2,
        productName: 'Steel Beams',
        sku: 'STL-002',
        currentStock: 80.0,
        averageDailyUsage: 20.0,
        reorderLevel: 20.0,
        estimatedDaysToReorder: 3.0,
        estimatedDaysToStockout: 4.0,
        hasSufficientHistory: true,
      ),
    ];

    final mockReorderList = [
      ReorderRecommendationItem(
        productId: 2,
        productName: 'Steel Beams',
        sku: 'STL-002',
        currentStock: 80.0,
        averageUsage: 20.0,
        targetCoverage: 30,
        recommendedReorderQuantity: 540.0,
        explanation: 'Formula: Target Need = (Avg Usage: 20.0/day × Coverage: 30 days) + Buffer: 20 = 620. Deficit = 620 - Current Stock (80) = 540.0 units recommended.',
        hasSufficientHistory: true,
      ),
    ];

    testWidgets('Renders Section 28 Stockout Velocity tab with transparent metrics and fallback message', (tester) async {
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            stockoutFutureProvider.overrideWith((ref) async => mockStockoutList),
            reorderFutureProvider.overrideWith((ref) async => mockReorderList),
          ],
          child: const MaterialApp(
            home: IntelligenceScreen(),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Check Header
      expect(find.text('Inventory Intelligence'), findsOneWidget);
      expect(find.text('Stockout Velocity'), findsOneWidget);
      expect(find.text('Reorder Recommendations'), findsOneWidget);

      // Check Product 1 (Insufficient history)
      expect(find.text('Titanium Fasteners'), findsOneWidget);
      expect(find.text('Not enough historical movement data.'), findsOneWidget);

      // Check Product 2 (Active history)
      expect(find.text('Steel Beams'), findsOneWidget);
      expect(find.text('4.0 days'), findsOneWidget);
      expect(find.text('3.0 days'), findsOneWidget);
      expect(find.text('20.0/day'), findsOneWidget);
    });

    testWidgets('Renders Section 28 Reorder Recommendations tab with transparent explanation card', (tester) async {
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            stockoutFutureProvider.overrideWith((ref) async => mockStockoutList),
            reorderFutureProvider.overrideWith((ref) async => mockReorderList),
          ],
          child: const MaterialApp(
            home: IntelligenceScreen(),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Switch to Reorder Recommendations Tab
      await tester.tap(find.text('Reorder Recommendations'));
      await tester.pumpAndSettle();

      // Verify Coverage Chips
      expect(find.text('15 Days'), findsOneWidget);
      expect(find.text('30 Days'), findsOneWidget);
      expect(find.text('60 Days'), findsOneWidget);

      // Verify Recommendation Quantity
      expect(find.text('540 units'), findsOneWidget);

      // Verify Transparent Explanation displayed to the user
      expect(find.text('Transparent Arithmetic Explanation'), findsOneWidget);
      expect(find.textContaining('Formula: Target Need'), findsOneWidget);
    });
  });
}
