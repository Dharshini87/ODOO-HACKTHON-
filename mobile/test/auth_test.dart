import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/material.dart';
import 'package:stocksense_mobile/features/auth/presentation/auth_provider.dart';
import 'package:stocksense_mobile/features/auth/presentation/login_screen.dart';
import 'package:stocksense_mobile/features/auth/presentation/register_screen.dart';
import 'package:stocksense_mobile/features/auth/presentation/forgot_password_screen.dart';
import 'package:stocksense_mobile/features/auth/presentation/otp_verification_screen.dart';
import 'package:stocksense_mobile/features/auth/presentation/reset_password_screen.dart';
import 'package:stocksense_mobile/core/providers/core_providers.dart';
import 'package:stocksense_mobile/core/storage/secure_storage.dart';
import 'package:stocksense_mobile/core/network/api_client.dart';
import 'package:stocksense_mobile/core/network/api_endpoints.dart';
import 'package:stocksense_mobile/core/errors/app_exception.dart';

class _FakeSecureStorage extends SecureStorageService {
  String? _token;
  String? _user;

  @override
  Future<void> saveToken(String token) async => _token = token;
  @override
  Future<String?> getToken() async => _token;
  @override
  Future<void> deleteToken() async => _token = null;

  @override
  Future<void> saveUser(String userJson) async => _user = userJson;
  @override
  Future<String?> getUser() async => _user;
  @override
  Future<void> deleteUser() async => _user = null;

  @override
  Future<void> clearAll() async {
    _token = null;
    _user = null;
  }
}

class _FakeApiClient extends ApiClient {
  Map<String, dynamic>? mockMeResponse;
  Map<String, dynamic>? mockLoginResponse;
  bool shouldThrowOnMe = false;
  bool shouldThrow401OnMe = false;

  _FakeApiClient({required super.storage});

  @override
  Future<Response<T>> post<T>(
    String path, {
    dynamic data,
    Map<String, dynamic>? queryParameters,
    Options? options,
  }) async {
    if (path == ApiEndpoints.login && mockLoginResponse != null) {
      return Response<T>(
        requestOptions: RequestOptions(path: path),
        data: mockLoginResponse as T,
        statusCode: 200,
      );
    }
    if (path == ApiEndpoints.forgotPassword) {
      return Response<T>(
        requestOptions: RequestOptions(path: path),
        data: {
          'message': 'Demo OTP generated.',
          'demo_otp': '123456',
          'is_demo': true,
        } as T,
        statusCode: 200,
      );
    }
    if (path == ApiEndpoints.verifyOtp) {
      final body = data as Map<String, dynamic>?;
      if (body?['otp'] != '123456') {
        throw Exception('Invalid OTP code. 4 attempt(s) remaining.');
      }
      return Response<T>(
        requestOptions: RequestOptions(path: path),
        data: {'message': 'OTP verified successfully.', 'valid': true} as T,
        statusCode: 200,
      );
    }
    if (path == ApiEndpoints.resetPassword) {
      return Response<T>(
        requestOptions: RequestOptions(path: path),
        data: {'message': 'Password reset successful.'} as T,
        statusCode: 200,
      );
    }
    return Response<T>(
      requestOptions: RequestOptions(path: path),
      data: {'access_token': 'dummy_token'} as T,
      statusCode: 200,
    );
  }

  @override
  Future<Response<T>> get<T>(
    String path, {
    Map<String, dynamic>? queryParameters,
    Options? options,
  }) async {
    if (path == ApiEndpoints.me) {
      if (shouldThrow401OnMe) {
        throw UnauthorizedException();
      }
      if (shouldThrowOnMe) {
        throw Exception('Network unreachable');
      }
      if (mockMeResponse != null) {
        return Response<T>(
          requestOptions: RequestOptions(path: path),
          data: mockMeResponse as T,
          statusCode: 200,
        );
      }
    }
    return Response<T>(
      requestOptions: RequestOptions(path: path),
      data: {} as T,
      statusCode: 200,
    );
  }
}

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
      expect(staff.hasPermission('access_system_settings'), isFalse);
      expect(staff.hasPermission('manage_system_settings'), isFalse);
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
      expect(manager.hasPermission('access_system_settings'), isTrue);
      expect(manager.hasPermission('manage_system_settings'), isTrue);
    });

    test('AuthUser role normalization standardizes roles', () {
      expect(AuthUser.normalizeRole('WAREHOUSE_STAFF'), equals('WAREHOUSE_STAFF'));
      expect(AuthUser.normalizeRole('staff'), equals('WAREHOUSE_STAFF'));
      expect(AuthUser.normalizeRole('Warehouse Staff'), equals('WAREHOUSE_STAFF'));
      expect(AuthUser.normalizeRole('INVENTORY_MANAGER'), equals('INVENTORY_MANAGER'));
      expect(AuthUser.normalizeRole('manager'), equals('INVENTORY_MANAGER'));
      expect(AuthUser.normalizeRole('Inventory Manager'), equals('INVENTORY_MANAGER'));
      expect(AuthUser.normalizeRole(null), equals('WAREHOUSE_STAFF'));
      expect(AuthUser.normalizeRole(''), equals('WAREHOUSE_STAFF'));
    });
  });

  group('RBAC Phase 4: Flutter Session Role Awareness Lifecycle Tests', () {
    late _FakeSecureStorage fakeStorage;
    late _FakeApiClient fakeApi;
    late ProviderContainer container;

    setUp(() {
      fakeStorage = _FakeSecureStorage();
      fakeApi = _FakeApiClient(storage: fakeStorage);
      container = ProviderContainer(
        overrides: [
          secureStorageProvider.overrideWithValue(fakeStorage),
          apiClientProvider.overrideWithValue(fakeApi),
        ],
      );
    });

    tearDown(() {
      container.dispose();
    });

    test('Login flow: JWT -> fetch authenticated user -> resolve backend role -> store in session', () async {
      fakeApi.mockLoginResponse = {
        'access_token': 'test_jwt_staff_token',
        'user_name': 'Staff Sam',
        'role': 'WAREHOUSE_STAFF',
        'user_id': 101,
      };
      fakeApi.mockMeResponse = {
        'id': 101,
        'name': 'Staff Sam',
        'email': 'sam@stocksense.demo',
        'role': 'WAREHOUSE_STAFF',
        'is_active': true,
        'is_manager': false,
      };

      final success = await container
          .read(authProvider.notifier)
          .login('sam@stocksense.demo', 'Pass123!');

      expect(success, isTrue);

      final state = container.read(authProvider);
      expect(state.isAuthenticated, isTrue);
      expect(state.currentUser, isNotNull);
      expect(state.currentUser!.role, equals('WAREHOUSE_STAFF'));
      expect(state.currentUser!.isStaff, isTrue);
      expect(state.currentUser!.isManager, isFalse);
      expect(state.currentRole, equals('WAREHOUSE_STAFF'));

      // Verify currentUserProvider
      expect(container.read(currentUserProvider)?.role, equals('WAREHOUSE_STAFF'));

      // Verify stored in session storage
      final storedToken = await fakeStorage.getToken();
      final storedUserRaw = await fakeStorage.getUser();
      expect(storedToken, equals('test_jwt_staff_token'));
      expect(storedUserRaw, contains('"role":"WAREHOUSE_STAFF"'));
    });

    test('Backend is authoritative: Login ignores client role claim and resolves database role', () async {
      // Login endpoint response might contain legacy or client-attempted claim
      fakeApi.mockLoginResponse = {
        'access_token': 'test_jwt_token',
        'user_name': 'Alex User',
        'role': 'INVENTORY_MANAGER',
        'user_id': 202,
      };
      // But /api/auth/me returns the authoritative database role
      fakeApi.mockMeResponse = {
        'id': 202,
        'name': 'Alex User',
        'email': 'alex@stocksense.demo',
        'role': 'WAREHOUSE_STAFF',
        'is_active': true,
        'is_manager': false,
      };

      await container
          .read(authProvider.notifier)
          .login('alex@stocksense.demo', 'Pass123!');

      final state = container.read(authProvider);
      // The session state role MUST match the backend /api/auth/me role
      expect(state.currentUser?.role, equals('WAREHOUSE_STAFF'));
      expect(state.currentUser?.isManager, isFalse);
      expect(state.currentUser?.isStaff, isTrue);
    });

    test('App restart & session restoration: verifies session with backend and updates role', () async {
      await fakeStorage.saveToken('existing_valid_jwt');
      await fakeStorage.saveUser(jsonEncode({
        'id': 303,
        'name': 'Elena',
        'email': 'elena@stocksense.demo',
        'role': 'WAREHOUSE_STAFF',
      }));

      // Backend now indicates user has been promoted to INVENTORY_MANAGER
      fakeApi.mockMeResponse = {
        'id': 303,
        'name': 'Elena',
        'email': 'elena@stocksense.demo',
        'role': 'INVENTORY_MANAGER',
        'is_active': true,
        'is_manager': true,
      };

      final restored = await container.read(authProvider.notifier).checkSession();
      expect(restored, isTrue);

      final state = container.read(authProvider);
      expect(state.isAuthenticated, isTrue);
      // Role is updated to the authoritative backend role
      expect(state.currentUser?.role, equals('INVENTORY_MANAGER'));
      expect(state.currentUser?.isManager, isTrue);
      expect(state.currentUser?.isStaff, isFalse);
    });

    test('Expired session: checkSession with 401 clears token, session, user, and role', () async {
      await fakeStorage.saveToken('expired_jwt');
      await fakeStorage.saveUser(jsonEncode({
        'id': 404,
        'name': 'Expired User',
        'email': 'expired@stocksense.demo',
        'role': 'WAREHOUSE_STAFF',
      }));

      fakeApi.shouldThrow401OnMe = true;

      final restored = await container.read(authProvider.notifier).checkSession();
      expect(restored, isFalse);

      final state = container.read(authProvider);
      expect(state.isAuthenticated, isFalse);
      expect(state.currentUser, isNull);
      expect(state.currentRole, isNull);

      // Storage is cleared
      expect(await fakeStorage.getToken(), isNull);
      expect(await fakeStorage.getUser(), isNull);
    });

    test('handleSessionExpired: clears token, session, user, and role state', () async {
      await fakeStorage.saveToken('active_token');
      await fakeStorage.saveUser(jsonEncode({
        'id': 505,
        'name': 'Active User',
        'email': 'user@stocksense.demo',
        'role': 'INVENTORY_MANAGER',
      }));

      await container.read(authProvider.notifier).handleSessionExpired();

      final state = container.read(authProvider);
      expect(state.isAuthenticated, isFalse);
      expect(state.currentUser, isNull);
      expect(state.currentRole, isNull);
      expect(await fakeStorage.getToken(), isNull);
      expect(await fakeStorage.getUser(), isNull);
    });

    test('Logout clears state, and subsequent login loads new backend role', () async {
      // 1. First user: Inventory Manager
      fakeApi.mockLoginResponse = {
        'access_token': 'manager_jwt',
        'user_name': 'Manager User',
        'role': 'INVENTORY_MANAGER',
        'user_id': 1,
      };
      fakeApi.mockMeResponse = {
        'id': 1,
        'name': 'Manager User',
        'email': 'manager@stocksense.demo',
        'role': 'INVENTORY_MANAGER',
        'is_active': true,
        'is_manager': true,
      };

      await container.read(authProvider.notifier).login('manager@stocksense.demo', 'Pass123!');
      expect(container.read(authProvider).currentUser?.role, equals('INVENTORY_MANAGER'));
      expect(container.read(authProvider).currentUser?.isManager, isTrue);

      // 2. Logout clears everything
      await container.read(authProvider.notifier).logout();
      expect(container.read(authProvider).isAuthenticated, isFalse);
      expect(container.read(authProvider).currentUser, isNull);
      expect(await fakeStorage.getToken(), isNull);

      // 3. Next user: Warehouse Staff
      fakeApi.mockLoginResponse = {
        'access_token': 'staff_jwt',
        'user_name': 'Staff User',
        'role': 'WAREHOUSE_STAFF',
        'user_id': 2,
      };
      fakeApi.mockMeResponse = {
        'id': 2,
        'name': 'Staff User',
        'email': 'staff@stocksense.demo',
        'role': 'WAREHOUSE_STAFF',
        'is_active': true,
        'is_manager': false,
      };

      await container.read(authProvider.notifier).login('staff@stocksense.demo', 'Pass123!');
      final state = container.read(authProvider);
      expect(state.isAuthenticated, isTrue);
      expect(state.currentUser?.role, equals('WAREHOUSE_STAFF'));
      expect(state.currentUser?.isStaff, isTrue);
      expect(state.currentUser?.isManager, isFalse);
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

    testWidgets('ForgotPasswordScreen renders clean UI without demo OTP or demo banner', (tester) async {
      final fakeStorage = _FakeSecureStorage();
      final fakeApi = _FakeApiClient(storage: fakeStorage);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            secureStorageProvider.overrideWithValue(fakeStorage),
            apiClientProvider.overrideWithValue(fakeApi),
          ],
          child: const MaterialApp(home: ForgotPasswordScreen()),
        ),
      );
      await tester.pumpAndSettle();

      // Verify clean UI elements
      expect(find.text('Reset Password'), findsOneWidget);
      expect(find.text('Email Address'), findsOneWidget);
      expect(find.text("We'll send a 6-digit code to this address."), findsOneWidget);
      expect(find.text('Send OTP Code'), findsOneWidget);
      expect(find.text('Back to Sign In'), findsOneWidget);

      // Verify no demo text or banners appear
      expect(find.text('OTP generated successfully'), findsNothing);
      expect(find.textContaining('Demo OTP'), findsNothing);
      expect(find.textContaining('Demo mode'), findsNothing);
      expect(find.text('Continue to Verification'), findsNothing);
    });

    testWidgets('OtpVerificationScreen displays clean UI without demo OTP banner', (tester) async {
      final fakeStorage = _FakeSecureStorage();
      final fakeApi = _FakeApiClient(storage: fakeStorage);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            secureStorageProvider.overrideWithValue(fakeStorage),
            apiClientProvider.overrideWithValue(fakeApi),
          ],
          child: const MaterialApp(
            home: OtpVerificationScreen(
              email: 'staff@stocksense.demo',
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Verify Your Email'), findsOneWidget);
      expect(find.text('staff@stocksense.demo'), findsOneWidget);
      expect(find.text('Verify Code'), findsOneWidget);
      expect(find.textContaining('Demo OTP'), findsNothing);
      expect(find.textContaining('Demo mode'), findsNothing);
    });

    testWidgets('ResetPasswordScreen renders new password fields and reset button', (tester) async {
      final fakeStorage = _FakeSecureStorage();
      final fakeApi = _FakeApiClient(storage: fakeStorage);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            secureStorageProvider.overrideWithValue(fakeStorage),
            apiClientProvider.overrideWithValue(fakeApi),
          ],
          child: const MaterialApp(
            home: ResetPasswordScreen(
              email: 'staff@stocksense.demo',
              otpCode: '123456',
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Create New Password'), findsOneWidget);
      expect(find.text('New Password'), findsOneWidget);
      expect(find.text('Confirm New Password'), findsOneWidget);
      expect(find.text('Reset Password'), findsOneWidget);
      expect(find.text('Back to Sign In'), findsOneWidget);
    });

    test('AuthNotifier verifyOtp success and failure with wrong OTP', () async {
      final fakeStorage = _FakeSecureStorage();
      final fakeApi = _FakeApiClient(storage: fakeStorage);

      final container = ProviderContainer(
        overrides: [
          secureStorageProvider.overrideWithValue(fakeStorage),
          apiClientProvider.overrideWithValue(fakeApi),
        ],
      );

      final notifier = container.read(authProvider.notifier);

      // Correct OTP
      final success = await notifier.verifyOtp(email: 'staff@stocksense.demo', otp: '123456');
      expect(success, isTrue);

      // Wrong OTP
      final failure = await notifier.verifyOtp(email: 'staff@stocksense.demo', otp: '000000');
      expect(failure, isFalse);
      expect(container.read(authProvider).errorMessage, contains('Invalid OTP code'));
    });
  });
}
