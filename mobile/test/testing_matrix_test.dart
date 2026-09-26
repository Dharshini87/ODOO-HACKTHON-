import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:stocksense_mobile/core/widgets/loading_view.dart';
import 'package:stocksense_mobile/core/widgets/empty_view.dart';
import 'package:stocksense_mobile/core/widgets/error_view.dart';
import 'package:stocksense_mobile/features/auth/presentation/auth_provider.dart';
import 'package:stocksense_mobile/features/adjustments/presentation/adjustment_detail_screen.dart';
import 'package:stocksense_mobile/features/receipts/presentation/create_receipt_screen.dart';
import 'package:stocksense_mobile/shared/providers/inventory_providers.dart';

void main() {
  group('Section 47: Navigation & Tab Switching', () {
    testWidgets('Bottom navigation switches tabs and updates body view', (tester) async {
      int activeIndex = 0;

      await tester.pumpWidget(
        StatefulBuilder(
          builder: (context, setState) {
            return MaterialApp(
              home: Scaffold(
                body: Center(
                  child: Text(
                    activeIndex == 0
                        ? 'Operations Home View'
                        : (activeIndex == 1 ? 'Stock Catalog View' : 'History Ledger View'),
                  ),
                ),
                bottomNavigationBar: NavigationBar(
                  selectedIndex: activeIndex,
                  onDestinationSelected: (index) => setState(() => activeIndex = index),
                  destinations: const [
                    NavigationDestination(icon: Icon(Icons.dashboard_rounded), label: 'Operations'),
                    NavigationDestination(icon: Icon(Icons.inventory_2_rounded), label: 'Stock'),
                    NavigationDestination(icon: Icon(Icons.history_rounded), label: 'History'),
                  ],
                ),
              ),
            );
          },
        ),
      );

      expect(find.text('Operations Home View'), findsOneWidget);
      expect(find.text('Stock Catalog View'), findsNothing);

      // Tap Stock tab
      await tester.tap(find.text('Stock'));
      await tester.pumpAndSettle();

      expect(find.text('Stock Catalog View'), findsOneWidget);
      expect(find.text('Operations Home View'), findsNothing);

      // Tap History tab
      await tester.tap(find.text('History'));
      await tester.pumpAndSettle();

      expect(find.text('History Ledger View'), findsOneWidget);
    });
  });
  group('Section 47: Authentication State Lifecycle', () {
    test('AuthState initial, copyWith, and unauthenticated state', () {
      const initial = AuthState();
      expect(initial.isAuthenticated, false);
      expect(initial.isLoading, false);
      expect(initial.user, isNull);

      final loggedIn = initial.copyWith(
        isAuthenticated: true,
        user: const AuthUser(
          id: 1,
          name: 'Sarah Manager',
          email: 'sarah@stocksense.com',
          role: 'INVENTORY_MANAGER',
        ),
      );
      expect(loggedIn.isAuthenticated, true);
      expect(loggedIn.user?.name, 'Sarah Manager');
      expect(loggedIn.user?.isManager, true);
      expect(loggedIn.user?.isStaff, false);
      expect(loggedIn.user?.hasPermission('validate_adjustment'), true);

      final loggedOut = loggedIn.copyWith(
        isAuthenticated: false,
        user: null,
      );
      expect(loggedOut.isAuthenticated, false);
    });

    test('AuthUser role and permission distinctions (Manager vs Staff)', () {
      const manager = AuthUser(
        id: 1,
        name: 'Manager Alice',
        email: 'alice@stocksense.com',
        role: 'INVENTORY_MANAGER',
      );
      const staff = AuthUser(
        id: 2,
        name: 'Staff Bob',
        email: 'bob@stocksense.com',
        role: 'WAREHOUSE_STAFF',
      );

      // Manager has full administrative authority
      expect(manager.isManager, true);
      expect(manager.isStaff, false);
      expect(manager.hasPermission('validate_adjustment'), true);
      expect(manager.hasPermission('manage_warehouses'), true);

      // Staff has restricted permissions
      expect(staff.isManager, false);
      expect(staff.isStaff, true);
      expect(staff.hasPermission('validate_adjustment'), false);
      expect(staff.hasPermission('manage_warehouses'), false);
    });
  });

  group('Section 47: Loading & Empty States', () {
    testWidgets('LoadingView renders circular progress indicator and informative message', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: LoadingView(message: 'Calculating ledger stock...'),
          ),
        ),
      );

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.text('Calculating ledger stock...'), findsOneWidget);
    });

    testWidgets('EmptyView renders title, subtitle, and action button', (tester) async {
      bool actionTriggered = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: EmptyView(
              title: 'No Move Records',
              subtitle: 'Transactions will appear here once processed',
              icon: Icons.history_rounded,
              actionLabel: 'Refresh',
              onAction: () => actionTriggered = true,
            ),
          ),
        ),
      );

      expect(find.text('No Move Records'), findsOneWidget);
      expect(find.text('Transactions will appear here once processed'), findsOneWidget);
      expect(find.byIcon(Icons.history_rounded), findsOneWidget);

      await tester.tap(find.text('Refresh'));
      await tester.pump();
      expect(actionTriggered, true);
    });

    testWidgets('ErrorView renders error message and retry button', (tester) async {
      bool retried = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ErrorView(
              message: 'Failed to connect to StockSense server',
              onRetry: () => retried = true,
            ),
          ),
        ),
      );

      expect(find.text('Failed to connect to StockSense server'), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);

      await tester.tap(find.text('Retry'));
      await tester.pump();
      expect(retried, true);
    });
  });

  group('Section 47: Provider States (AsyncLoading, AsyncData, AsyncError)', () {
    testWidgets('AsyncValue.loading renders LoadingView message', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Consumer(
              builder: (context, ref, _) {
                const asyncState = AsyncValue<String>.loading();
                return asyncState.when(
                  loading: () => const LoadingView(message: 'Loading ledger audit trail...'),
                  data: (data) => Text(data),
                  error: (e, _) => Text('Error: $e'),
                );
              },
            ),
          ),
        ),
      );

      expect(find.byType(LoadingView), findsOneWidget);
      expect(find.text('Loading ledger audit trail...'), findsOneWidget);
    });

    testWidgets('AsyncValue.data renders content card', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Consumer(
              builder: (context, ref, _) {
                const asyncState = AsyncValue<String>.data('100 kg Steel Rod Received');
                return asyncState.when(
                  loading: () => const LoadingView(),
                  data: (data) => Text(data, key: const Key('data_view')),
                  error: (e, _) => Text('Error: $e'),
                );
              },
            ),
          ),
        ),
      );

      expect(find.byKey(const Key('data_view')), findsOneWidget);
      expect(find.text('100 kg Steel Rod Received'), findsOneWidget);
    });

    testWidgets('AsyncValue.error renders ErrorView with retry', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Consumer(
              builder: (context, ref, _) {
                final asyncState = AsyncValue<String>.error('500 Internal Server Error', StackTrace.empty);
                return asyncState.when(
                  loading: () => const LoadingView(),
                  data: (data) => Text(data),
                  error: (e, _) => ErrorView(message: e.toString()),
                );
              },
            ),
          ),
        ),
      );

      expect(find.byType(ErrorView), findsOneWidget);
      expect(find.text('500 Internal Server Error'), findsOneWidget);
    });
  });

  group('Section 47: Forms & Input Validation', () {
    testWidgets('CreateReceiptScreen validates empty form input', (tester) async {
      tester.view.physicalSize = const Size(1200, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            productsFutureProvider.overrideWith((ref) => Future.value([])),
            locationsFutureProvider.overrideWith((ref) => Future.value([])),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: CreateReceiptScreen(),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Submit without entering product or quantity
      final submitBtn = find.text('Create Draft Receipt');
      expect(submitBtn, findsOneWidget);

      await tester.tap(submitBtn);
      await tester.pump();

      // Form validation errors displayed
      expect(find.text('Please select a product'), findsOneWidget);
    });
  });

  group('Section 47: Role-Specific UI Rendering', () {
    final mockAdjustment = StockMoveItem(
      id: 55,
      reference: 'ADJ-2026-005',
      moveType: 'ADJUSTMENT',
      productId: 1,
      productName: 'Steel Rod',
      sku: 'SR-100',
      fromLocationId: 1,
      fromLocationName: 'Rack A',
      toLocationId: 0,
      toLocationName: '',
      quantity: 3.0,
      status: 'draft',
      systemQuantity: 80.0,
      physicalCount: 77.0,
      difference: -3.0,
      reason: 'Damaged',
    );

    testWidgets('Inventory Manager sees active Validate Adjustment button', (tester) async {
      tester.view.physicalSize = const Size(1200, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authProvider.overrideWith(() => _MockAuthNotifier(
              const AuthState(
                isAuthenticated: true,
                user: AuthUser(
                  id: 1,
                  name: 'Sarah Manager',
                  email: 'sarah@stocksense.com',
                  role: 'INVENTORY_MANAGER',
                ),
              ),
            )),
          ],
          child: MaterialApp(
            home: AdjustmentDetailScreen(initialAdjustment: mockAdjustment),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Manager has Validate Adjustment button
      expect(find.text('Validate Adjustment'), findsOneWidget);
    });

    testWidgets('Warehouse Staff does NOT see Validate Adjustment button and sees approval notice', (tester) async {
      tester.view.physicalSize = const Size(1200, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authProvider.overrideWith(() => _MockAuthNotifier(
              const AuthState(
                isAuthenticated: true,
                user: AuthUser(
                  id: 2,
                  name: 'Bob Staff',
                  email: 'bob@stocksense.com',
                  role: 'WAREHOUSE_STAFF',
                ),
              ),
            )),
          ],
          child: MaterialApp(
            home: AdjustmentDetailScreen(initialAdjustment: mockAdjustment),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Staff does NOT see Validate Adjustment button
      expect(find.text('Validate Adjustment'), findsNothing);

      // Staff sees notice that manager validation is required
      expect(find.text('Pending Manager Validation'), findsOneWidget);
      expect(find.textContaining('Warehouse Staff can draft adjustments'), findsOneWidget);
    });
  });
}

class _MockAuthNotifier extends AuthNotifier {
  final AuthState _mockState;
  _MockAuthNotifier(this._mockState);

  @override
  AuthState build() => _mockState;
}
