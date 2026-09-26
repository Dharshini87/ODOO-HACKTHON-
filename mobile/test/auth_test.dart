import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/material.dart';
import 'package:stocksense_mobile/features/auth/presentation/auth_provider.dart';
import 'package:stocksense_mobile/features/auth/presentation/login_screen.dart';
import 'package:stocksense_mobile/features/auth/presentation/register_screen.dart';
import 'package:stocksense_mobile/features/auth/presentation/forgot_password_screen.dart';

void main() {
  group('Section 6 RBAC and AuthUser Tests', () {
    test('Warehouse Staff role and permissions check', () {
      const staff = AuthUser(
        id: 1,
        name: 'Staff John',
        email: 'staff@test.com',
        role: 'WAREHOUSE_STAFF',
      );

      expect(staff.isManager, isFalse);
      expect(staff.isStaff, isTrue);

      // Staff allowed actions
      expect(staff.hasPermission('view_dashboard'), isTrue);
      expect(staff.hasPermission('view_stock'), isTrue);
      expect(staff.hasPermission('create_receipt'), isTrue);
      expect(staff.hasPermission('validate_receipt'), isTrue);
      expect(staff.hasPermission('create_delivery'), isTrue);
      expect(staff.hasPermission('validate_delivery'), isTrue);
      expect(staff.hasPermission('create_transfer'), isTrue);
      expect(staff.hasPermission('validate_transfer'), isTrue);
      expect(staff.hasPermission('create_adjustment'), isTrue);

      // Staff restricted actions (Manager only)
      expect(staff.hasPermission('validate_adjustment'), isFalse);
      expect(staff.hasPermission('manage_products'), isFalse);
      expect(staff.hasPermission('manage_categories'), isFalse);
      expect(staff.hasPermission('manage_warehouses'), isFalse);
      expect(staff.hasPermission('manage_locations'), isFalse);
      expect(staff.hasPermission('cancel_other_transaction'), isFalse);
    });

    test('Inventory Manager role and permissions check', () {
      const manager = AuthUser(
        id: 2,
        name: 'Manager Sarah',
        email: 'manager@test.com',
        role: 'INVENTORY_MANAGER',
      );

      expect(manager.isManager, isTrue);
      expect(manager.isStaff, isFalse);

      // Manager can perform all actions
      expect(manager.hasPermission('validate_adjustment'), isTrue);
      expect(manager.hasPermission('manage_products'), isTrue);
      expect(manager.hasPermission('manage_categories'), isTrue);
      expect(manager.hasPermission('manage_warehouses'), isTrue);
      expect(manager.hasPermission('manage_locations'), isTrue);
      expect(manager.hasPermission('cancel_other_transaction'), isTrue);
    });
  });

  group('Auth Screens Widget Tests', () {
    testWidgets('LoginScreen renders email, password, and sign in button', (tester) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(home: LoginScreen()),
        ),
      );
      await tester.pump();

      expect(find.text('Sign In'), findsWidgets);
      expect(find.text('Email Address'), findsOneWidget);
      expect(find.text('Password'), findsOneWidget);
      expect(find.text('Forgot Password?'), findsOneWidget);
      expect(find.text('Sign Up'), findsOneWidget);
    });

    testWidgets('RegisterScreen renders role selection and fields', (tester) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(home: RegisterScreen()),
        ),
      );
      await tester.pump();

      expect(find.text('Create Account'), findsWidgets);
      expect(find.text('Full Name'), findsOneWidget);
      expect(find.text('Email Address'), findsOneWidget);
      expect(find.text('Warehouse Staff'), findsOneWidget);
      expect(find.text('Inventory Manager'), findsOneWidget);
      expect(find.text('Confirm Password'), findsOneWidget);
    });

    testWidgets('ForgotPasswordScreen renders email and reset button', (tester) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(home: ForgotPasswordScreen()),
        ),
      );
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('Reset Password'), findsOneWidget);
      expect(find.text('Email Address'), findsOneWidget);
      expect(find.text('Send OTP Code'), findsOneWidget);
    });
  });
}
