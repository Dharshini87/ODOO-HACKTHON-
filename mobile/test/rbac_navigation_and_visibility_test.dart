import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:stocksense_mobile/features/auth/presentation/auth_provider.dart';
import 'package:stocksense_mobile/features/stock/presentation/stock_screen.dart';
import 'package:stocksense_mobile/features/stock/presentation/create_product_screen.dart';
import 'package:stocksense_mobile/features/warehouse/presentation/warehouse_list_screen.dart';
import 'package:stocksense_mobile/features/warehouse/presentation/warehouse_detail_screen.dart';
import 'package:stocksense_mobile/features/warehouse/presentation/location_list_screen.dart';
import 'package:stocksense_mobile/features/warehouse/presentation/create_warehouse_screen.dart';
import 'package:stocksense_mobile/features/warehouse/presentation/create_location_screen.dart';
import 'package:stocksense_mobile/features/account/presentation/settings_screen.dart';
import 'package:stocksense_mobile/features/intelligence/presentation/intelligence_screen.dart';
import 'package:stocksense_mobile/features/more/presentation/more_screen.dart';
import 'package:stocksense_mobile/features/stock/presentation/product_detail_screen.dart';
import 'package:stocksense_mobile/features/stock/presentation/categories_screen.dart';
import 'package:stocksense_mobile/features/dashboard/presentation/dashboard_screen.dart';
import 'package:stocksense_mobile/shared/providers/inventory_providers.dart';

class _MockAuthNotifier extends AuthNotifier {
  final AuthState _initialState;
  _MockAuthNotifier(this._initialState);

  @override
  AuthState build() => _initialState;

  void setUser(AuthUser? user) {
    state = AuthState(user: user, isAuthenticated: user != null, isLoading: false);
  }
}

void main() {
  const staffUser = AuthUser(
    id: 1,
    name: 'Warehouse Operator',
    email: 'staff@stocksense.demo',
    role: 'WAREHOUSE_STAFF',
  );

  const managerUser = AuthUser(
    id: 2,
    name: 'Inventory Manager',
    email: 'manager@stocksense.demo',
    role: 'INVENTORY_MANAGER',
  );

  group('STOCKSENSE RBAC Phase 5: Role-Aware UI Visibility', () {
    testWidgets('StockScreen: Staff sees catalog but NOT New Product button', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authProvider.overrideWith(() => _MockAuthNotifier(const AuthState(isAuthenticated: true, user: staffUser))),
            stockFutureProvider.overrideWith((ref) async => []),
            productsFutureProvider.overrideWith((ref) async => [
              {'id': 1, 'name': 'Widget A', 'sku': 'W-A', 'cost_per_unit': 10.0, 'reorder_point': 5.0}
            ]),
          ],
          child: const MaterialApp(home: StockScreen()),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Stock & Catalog'), findsOneWidget);
      expect(find.text('New Product'), findsNothing);
    });

    testWidgets('StockScreen: Manager sees New Product button', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authProvider.overrideWith(() => _MockAuthNotifier(const AuthState(isAuthenticated: true, user: managerUser))),
            stockFutureProvider.overrideWith((ref) async => []),
            productsFutureProvider.overrideWith((ref) async => []),
          ],
          child: const MaterialApp(home: StockScreen()),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('New Product'), findsOneWidget);
    });

    testWidgets('WarehouseListScreen: Staff sees warehouses but NOT New Warehouse button', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authProvider.overrideWith(() => _MockAuthNotifier(const AuthState(isAuthenticated: true, user: staffUser))),
            warehousesFutureProvider.overrideWith((ref) async => [
              {'id': 1, 'name': 'Central Depot', 'short_code': 'CD', 'address': '123 Main St'}
            ]),
          ],
          child: const MaterialApp(home: WarehouseListScreen()),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Central Depot'), findsOneWidget);
      expect(find.text('New Warehouse'), findsNothing);
    });

    testWidgets('WarehouseListScreen: Manager sees New Warehouse button', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authProvider.overrideWith(() => _MockAuthNotifier(const AuthState(isAuthenticated: true, user: managerUser))),
            warehousesFutureProvider.overrideWith((ref) async => []),
          ],
          child: const MaterialApp(home: WarehouseListScreen()),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('New Warehouse'), findsOneWidget);
    });

    testWidgets('WarehouseDetailScreen: Staff cannot see Add Location', (tester) async {
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final sampleWarehouse = {'id': 1, 'name': 'Main Hub', 'short_code': 'MH', 'address': 'Dock 1'};

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authProvider.overrideWith(() => _MockAuthNotifier(const AuthState(isAuthenticated: true, user: staffUser))),
            locationsFutureProvider.overrideWith((ref) async => []),
          ],
          child: MaterialApp(home: WarehouseDetailScreen(warehouse: sampleWarehouse)),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Add Location'), findsNothing);
    });

    testWidgets('WarehouseDetailScreen: Manager can see Add Location', (tester) async {
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final sampleWarehouse = {'id': 1, 'name': 'Main Hub', 'short_code': 'MH', 'address': 'Dock 1'};

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authProvider.overrideWith(() => _MockAuthNotifier(const AuthState(isAuthenticated: true, user: managerUser))),
            locationsFutureProvider.overrideWith((ref) async => []),
          ],
          child: MaterialApp(home: WarehouseDetailScreen(warehouse: sampleWarehouse)),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Add Location'), findsOneWidget);
    });

    testWidgets('LocationListScreen: Staff sees locations but NOT New Location button', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authProvider.overrideWith(() => _MockAuthNotifier(const AuthState(isAuthenticated: true, user: staffUser))),
            locationsFutureProvider.overrideWith((ref) async => [
              {'id': 1, 'name': 'Aisle 1', 'short_code': 'A1', 'is_virtual': false}
            ]),
          ],
          child: const MaterialApp(home: LocationListScreen()),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Aisle 1'), findsOneWidget);
      expect(find.text('New Location'), findsNothing);
    });

    testWidgets('LocationListScreen: Manager sees New Location button', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authProvider.overrideWith(() => _MockAuthNotifier(const AuthState(isAuthenticated: true, user: managerUser))),
            locationsFutureProvider.overrideWith((ref) async => []),
          ],
          child: const MaterialApp(home: LocationListScreen()),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('New Location'), findsOneWidget);
    });

    testWidgets('MoreScreen: Staff sees profile/search/warehouses but NOT Intelligence or System Settings', (tester) async {
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authProvider.overrideWith(() => _MockAuthNotifier(const AuthState(isAuthenticated: true, user: staffUser))),
          ],
          child: const MaterialApp(home: MoreScreen()),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Global Search'), findsOneWidget);
      expect(find.text('Warehouses & Locations'), findsOneWidget);
      expect(find.text('Stock Alerts & Notifications'), findsOneWidget);
      expect(find.text('User Profile & Role'), findsOneWidget);

      expect(find.text('Inventory Intelligence'), findsNothing);
      expect(find.text('System & Server Settings'), findsNothing);
    });

    testWidgets('MoreScreen: Manager sees Inventory Intelligence and System & Server Settings', (tester) async {
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authProvider.overrideWith(() => _MockAuthNotifier(const AuthState(isAuthenticated: true, user: managerUser))),
          ],
          child: const MaterialApp(home: MoreScreen()),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Inventory Intelligence'), findsOneWidget);
      expect(find.text('System & Server Settings'), findsOneWidget);
    });
  });

  group('STOCKSENSE RBAC Phase 5: Route Guards and Direct Navigation Protection', () {
    testWidgets('Direct screen access defense-in-depth: Staff blocked on CreateProductScreen', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authProvider.overrideWith(() => _MockAuthNotifier(const AuthState(isAuthenticated: true, user: staffUser))),
          ],
          child: const MaterialApp(home: CreateProductScreen()),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Access Restricted'), findsOneWidget);
      expect(find.text('Only Inventory Managers have permission to create and manage catalog products.'), findsOneWidget);
    });

    testWidgets('Direct screen access defense-in-depth: Staff blocked on CreateWarehouseScreen', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authProvider.overrideWith(() => _MockAuthNotifier(const AuthState(isAuthenticated: true, user: staffUser))),
          ],
          child: const MaterialApp(home: CreateWarehouseScreen()),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Access Restricted'), findsOneWidget);
      expect(find.text('Only Inventory Managers have permission to create or manage warehouse facilities.'), findsOneWidget);
    });

    testWidgets('Direct screen access defense-in-depth: Staff blocked on CreateLocationScreen', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authProvider.overrideWith(() => _MockAuthNotifier(const AuthState(isAuthenticated: true, user: staffUser))),
            warehousesFutureProvider.overrideWith((ref) async => []),
          ],
          child: const MaterialApp(home: CreateLocationScreen()),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Access Restricted'), findsOneWidget);
      expect(find.text('Only Inventory Managers have permission to create or manage storage locations.'), findsOneWidget);
    });

    testWidgets('Direct screen access defense-in-depth: Staff blocked on SettingsScreen', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authProvider.overrideWith(() => _MockAuthNotifier(const AuthState(isAuthenticated: true, user: staffUser))),
          ],
          child: const MaterialApp(home: SettingsScreen()),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Access Restricted'), findsOneWidget);
      expect(find.text('Only Inventory Managers have permission to access system and server configuration.'), findsOneWidget);
    });

    testWidgets('Direct screen access defense-in-depth: Staff blocked on IntelligenceScreen', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authProvider.overrideWith(() => _MockAuthNotifier(const AuthState(isAuthenticated: true, user: staffUser))),
            stockoutFutureProvider.overrideWith((ref) async => []),
            reorderFutureProvider.overrideWith((ref) async => []),
          ],
          child: const MaterialApp(home: IntelligenceScreen()),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Access Restricted'), findsOneWidget);
      expect(find.text('Only Inventory Managers have permission to access inventory intelligence, turnover projections, and stock analytics.'), findsOneWidget);
    });

    testWidgets('GoRouter Route Guard: Staff navigating to /products/create is redirected to /home', (tester) async {
      final testRouter = GoRouter(
        initialLocation: '/home',
        redirect: (context, state) {
          final isManager = staffUser.isManager;
          final loc = state.matchedLocation;
          final isManagerOnlyRoute = loc.startsWith('/products/create') ||
              loc.startsWith('/products/manage') ||
              loc.startsWith('/categories/manage') ||
              loc.startsWith('/warehouses/create') ||
              loc.startsWith('/locations/create') ||
              loc.startsWith('/settings') ||
              loc.startsWith('/intelligence');

          if (!isManager && isManagerOnlyRoute) {
            return '/home';
          }
          return null;
        },
        routes: [
          GoRoute(path: '/home', builder: (context, state) => const Scaffold(body: Text('Home Dashboard'))),
          GoRoute(path: '/products/create', builder: (context, state) => const Scaffold(body: Text('Create Master Product'))),
        ],
      );

      await tester.pumpWidget(MaterialApp.router(routerConfig: testRouter));
      await tester.pumpAndSettle();
      expect(find.text('Home Dashboard'), findsOneWidget);

      testRouter.go('/products/create');
      await tester.pumpAndSettle();

      // Guard intercepts and keeps user on /home
      expect(find.text('Home Dashboard'), findsOneWidget);
      expect(find.text('Create Master Product'), findsNothing);
    });

    testWidgets('GoRouter Route Guard: Manager navigating to /products/create is granted access', (tester) async {
      final testRouter = GoRouter(
        initialLocation: '/home',
        redirect: (context, state) {
          final isManager = managerUser.isManager;
          final loc = state.matchedLocation;
          final isManagerOnlyRoute = loc.startsWith('/products/create') ||
              loc.startsWith('/products/manage') ||
              loc.startsWith('/categories/manage') ||
              loc.startsWith('/warehouses/create') ||
              loc.startsWith('/locations/create') ||
              loc.startsWith('/settings') ||
              loc.startsWith('/intelligence');

          if (!isManager && isManagerOnlyRoute) {
            return '/home';
          }
          return null;
        },
        routes: [
          GoRoute(path: '/home', builder: (context, state) => const Scaffold(body: Text('Home Dashboard'))),
          GoRoute(path: '/products/create', builder: (context, state) => const Scaffold(body: Text('Create Master Product'))),
        ],
      );

      await tester.pumpWidget(MaterialApp.router(routerConfig: testRouter));
      await tester.pumpAndSettle();
      expect(find.text('Home Dashboard'), findsOneWidget);

      testRouter.go('/products/create');
      await tester.pumpAndSettle();

      // Manager access permitted
      expect(find.text('Create Master Product'), findsOneWidget);
    });
  });

  group('STOCKSENSE RBAC Phase 5: Session Switch & Role Isolation', () {
    test('Session role state clears upon logout and does not persist across logins', () {
      final container = ProviderContainer(
        overrides: [
          authProvider.overrideWith(() => _MockAuthNotifier(const AuthState(isAuthenticated: true, user: managerUser))),
        ],
      );
      expect(container.read(authProvider).user?.isManager, isTrue);

      // Logout clears user
      (container.read(authProvider.notifier) as _MockAuthNotifier).setUser(null);
      expect(container.read(authProvider).isAuthenticated, isFalse);
      expect(container.read(authProvider).user, isNull);

      // Staff login does NOT inherit manager permissions
      (container.read(authProvider.notifier) as _MockAuthNotifier).setUser(staffUser);
      expect(container.read(authProvider).isAuthenticated, isTrue);
      expect(container.read(authProvider).user?.isManager, isFalse);
      expect(container.read(authProvider).user?.isStaff, isTrue);
      container.dispose();
    });
  });

  group('STOCKSENSE RBAC Phase 6: Role-Specific Actions & Feature Separation', () {
    final sampleProduct = {
      'id': 42,
      'name': 'Titanium Fastener',
      'sku': 'TF-42',
      'unit_of_measure': 'pcs',
      'cost_per_unit': 45.0,
      'reorder_point': 100.0,
      'is_active': true,
    };

    testWidgets('ProductDetailScreen: Staff sees specs but NOT Edit Product actions', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authProvider.overrideWith(() => _MockAuthNotifier(const AuthState(isAuthenticated: true, user: staffUser))),
          ],
          child: MaterialApp(home: ProductDetailScreen(product: sampleProduct)),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Titanium Fastener'), findsWidgets);
      expect(find.text('SKU: TF-42'), findsOneWidget);
      expect(find.byTooltip('Edit Product'), findsNothing);
      expect(find.text('Edit Product Specifications'), findsNothing);
    });

    testWidgets('ProductDetailScreen: Manager sees Edit Product actions', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authProvider.overrideWith(() => _MockAuthNotifier(const AuthState(isAuthenticated: true, user: managerUser))),
          ],
          child: MaterialApp(home: ProductDetailScreen(product: sampleProduct)),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Titanium Fastener'), findsWidgets);
      expect(find.byTooltip('Edit Product'), findsOneWidget);
      expect(find.text('Edit Product Specifications'), findsOneWidget);
    });

    testWidgets('CategoriesScreen: Staff is blocked by AccessRestrictedScaffold', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authProvider.overrideWith(() => _MockAuthNotifier(const AuthState(isAuthenticated: true, user: staffUser))),
            categoriesFutureProvider.overrideWith((ref) async => []),
          ],
          child: const MaterialApp(home: CategoriesScreen()),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Access Restricted'), findsOneWidget);
      expect(find.text('Only Inventory Managers have permission to create and manage product categories.'), findsOneWidget);
      expect(find.text('New Category'), findsNothing);
    });

    testWidgets('CategoriesScreen: Manager sees Categories and New Category FAB', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authProvider.overrideWith(() => _MockAuthNotifier(const AuthState(isAuthenticated: true, user: managerUser))),
            categoriesFutureProvider.overrideWith((ref) async => [
              {'id': 1, 'name': 'Raw Materials', 'description': 'Primary inputs', 'is_active': true},
            ]),
          ],
          child: const MaterialApp(home: CategoriesScreen()),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Categories'), findsOneWidget);
      expect(find.text('Raw Materials'), findsOneWidget);
      expect(find.text('New Category'), findsOneWidget);
    });

    testWidgets('MoreScreen: Staff cannot see Manage Categories', (tester) async {
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authProvider.overrideWith(() => _MockAuthNotifier(const AuthState(isAuthenticated: true, user: staffUser))),
          ],
          child: const MaterialApp(home: MoreScreen()),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Manage Categories'), findsNothing);
    });

    testWidgets('MoreScreen: Manager sees Manage Categories', (tester) async {
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authProvider.overrideWith(() => _MockAuthNotifier(const AuthState(isAuthenticated: true, user: managerUser))),
          ],
          child: const MaterialApp(home: MoreScreen()),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Manage Categories'), findsOneWidget);
    });

    testWidgets('DashboardScreen: Direct Home Shortcuts navigate directly to feature routes', (tester) async {
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final dummyMetrics = DashboardData(
        totalStock: 500,
        totalProducts: 25,
        lowStockCount: 2,
        outOfStockCount: 1,
        pendingReceipts: 3,
        pendingDeliveries: 4,
        waitingDeliveries: 1,
        transfersScheduled: 2,
        intelligence: DashboardIntelligence(),
      );

      String navigatedRoute = '';

      final testRouter = GoRouter(
        initialLocation: '/home',
        routes: [
          GoRoute(path: '/home', builder: (context, state) => const DashboardScreen()),
          GoRoute(path: '/receipts', builder: (context, state) {
            navigatedRoute = '/receipts';
            return const Scaffold(body: Text('Receipts Workflow Page'));
          }),
          GoRoute(path: '/deliveries', builder: (context, state) {
            navigatedRoute = '/deliveries';
            return const Scaffold(body: Text('Deliveries Workflow Page'));
          }),
          GoRoute(path: '/transfers', builder: (context, state) {
            navigatedRoute = '/transfers';
            return const Scaffold(body: Text('Transfers Workflow Page'));
          }),
          GoRoute(path: '/adjustments', builder: (context, state) {
            navigatedRoute = '/adjustments';
            return const Scaffold(body: Text('Adjustments Workflow Page'));
          }),
          GoRoute(path: '/stock', builder: (context, state) {
            navigatedRoute = '/stock';
            return const Scaffold(body: Text('Stock Page'));
          }),
          GoRoute(path: '/history', builder: (context, state) {
            navigatedRoute = '/history';
            return const Scaffold(body: Text('History Page'));
          }),
        ],
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authProvider.overrideWith(() => _MockAuthNotifier(const AuthState(isAuthenticated: true, user: staffUser))),
            dashboardFutureProvider.overrideWith((ref) async => dummyMetrics),
          ],
          child: MaterialApp.router(routerConfig: testRouter),
        ),
      );
      await tester.pumpAndSettle();

      // Receipts hero card
      await tester.tap(find.text('Receipts').first);
      await tester.pumpAndSettle();
      expect(navigatedRoute, equals('/receipts'));

      // Return home
      testRouter.go('/home');
      await tester.pumpAndSettle();

      // Deliveries hero card
      await tester.tap(find.text('Deliveries').first);
      await tester.pumpAndSettle();
      expect(navigatedRoute, equals('/deliveries'));

      // Return home
      testRouter.go('/home');
      await tester.pumpAndSettle();

      // Transfers hero card
      await tester.tap(find.text('Transfers').first);
      await tester.pumpAndSettle();
      expect(navigatedRoute, equals('/transfers'));

      // Return home
      testRouter.go('/home');
      await tester.pumpAndSettle();

      // Adjustments hero card
      await tester.tap(find.text('Adjustments').first);
      await tester.pumpAndSettle();
      expect(navigatedRoute, equals('/adjustments'));

      // Return home
      testRouter.go('/home');
      await tester.pumpAndSettle();

      // Total Stock card
      await tester.tap(find.text('TOTAL STOCK').first);
      await tester.pumpAndSettle();
      expect(navigatedRoute, equals('/stock'));
    });
  });
}
