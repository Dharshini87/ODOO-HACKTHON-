# MODULE 01: 01_FLUTTER_FOUNDATION

============================================================
3. MOBILE APPLICATION STRUCTURE
============================================================

Use a feature-oriented Flutter architecture.

Recommended structure:

lib/
    main.dart

    app/
        app.dart
        router.dart
        theme/
            app_theme.dart
            app_colors.dart
            app_text_styles.dart
            app_spacing.dart

    core/
        network/
            api_client.dart
            api_endpoints.dart
            auth_interceptor.dart

        storage/
            secure_storage.dart

        errors/
            app_exception.dart

        widgets/
            app_button.dart
            app_text_field.dart
            status_badge.dart
            loading_view.dart
            error_view.dart
            empty_view.dart
            app_card.dart

        utils/

    features/
        auth/
        dashboard/
        products/
        stock/
        receipts/
        deliveries/
        transfers/
        adjustments/
        move_history/
        ledger/
        intelligence/
        warehouses/
        locations/
        notifications/
        profile/

    shared/
        models/
        widgets/

Each feature should contain appropriate:

data/
domain/
presentation/

Do not over-engineer the application with unnecessary abstractions.

============================================================
4. MOBILE NAVIGATION
============================================================

Use five bottom-navigation destinations:

HOME
OPERATIONS
STOCK
HISTORY
MORE

HOME:
Dashboard

OPERATIONS:
Receipts
Deliveries
Transfers
Adjustments

STOCK:
Stock
Products

HISTORY:
Move History
Stock Ledger

MORE:
Inventory Intelligence
Warehouses
Locations
Notifications
Profile
Settings

Use native mobile navigation.

Use:

- AppBar
- BottomNavigationBar / NavigationBar
- Bottom sheets
- Floating action buttons
- Sticky bottom actions
- Mobile cards
- Full-screen forms
- Pull-to-refresh
- Snackbars
- Confirmation dialogs

Do NOT create a desktop sidebar.

Do NOT create desktop-style tables.

============================================================
30. MOBILE UI REQUIREMENTS
============================================================

Use the existing StockSense mobile design system.

Do not redesign the existing authentication screens if they already exist in the project.

Use:

- Inter typography
- Existing StockSense colors
- Existing button styles
- Existing input styles
- Existing status badges
- Existing card language

Mobile-first.

Target:

390 × 844

Support:

360 × 800
412 × 915

Use:

- Bottom navigation
- Cards
- Bottom sheets
- Full-screen forms
- Sticky action buttons
- Floating action buttons
- Search screens
- Filter sheets
- Pull-to-refresh
- Snackbars
- Confirmation dialogs

Do not create desktop tables.

============================================================
37. API CLIENT
============================================================

Create one central Dio client.

Responsibilities:

- Base URL
- JWT injection
- Timeout
- Error handling
- 401 handling
- Logging during development

Do not create separate HTTP clients in every screen.

Architecture:

Flutter Screen
↓
Riverpod Provider
↓
Repository
↓
Dio ApiClient
↓
FastAPI

============================================================
38. STATE MANAGEMENT
============================================================

Use Riverpod.

Create providers for:

Auth
Dashboard
Products
Stock
Receipts
Deliveries
Transfers
Adjustments
Move History
Ledger
Intelligence
Warehouses
Locations
Notifications

UI should react to provider state.

Do not place API calls directly inside UI widgets.

============================================================
39. REPOSITORY PATTERN
============================================================

Use:

UI
↓
Provider
↓
Repository
↓
API Client
↓
Backend

Repositories should abstract network calls.

Example:

DeliveryRepository

Methods:

createDelivery()
getDeliveries()
getDelivery()
validateDelivery()
cancelDelivery()

============================================================
45. FLUTTER PROJECT STRUCTURE
============================================================

Create:

lib/
    main.dart

    app/

    core/

    features/
        auth/
        dashboard/
        products/
        stock/
        receipts/
        deliveries/
        transfers/
        adjustments/
        move_history/
        ledger/
        intelligence/
        warehouses/
        locations/
        notifications/
        profile/

    shared/

Keep features modular.

============================================================
