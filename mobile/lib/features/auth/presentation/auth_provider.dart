import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/providers/core_providers.dart';
import '../../../core/network/api_endpoints.dart';
import '../../../core/network/api_client.dart';
import '../../../core/storage/secure_storage.dart';
import '../../../core/errors/app_exception.dart';

class AuthUser {
  static const String roleWarehouseStaff = 'WAREHOUSE_STAFF';
  static const String roleInventoryManager = 'INVENTORY_MANAGER';

  final int? id;
  final String name;
  final String email;
  final String role;

  const AuthUser({
    this.id,
    required this.name,
    required this.email,
    required this.role,
  });

  static String normalizeRole(String? raw) {
    if (raw == null || raw.trim().isEmpty) return roleWarehouseStaff;
    final upper = raw.trim().toUpperCase();
    if (upper.contains('MANAGE')) {
      return roleInventoryManager;
    }
    return roleWarehouseStaff;
  }

  bool get isManager => role.toUpperCase().contains('MANAGE');
  bool get isStaff => !isManager;

  bool hasPermission(String permission) {
    if (isManager) return true;
    final managerOnly = {
      'validate_adjustment',
      'manage_products',
      'manage_categories',
      'manage_warehouses',
      'manage_locations',
      'cancel_other_transaction',
      'access_system_settings',
      'manage_system_settings',
    };
    return !managerOnly.contains(permission.toLowerCase().trim());
  }

  factory AuthUser.fromJson(Map<String, dynamic> json) {
    return AuthUser(
      id: json['id'] as int? ?? json['user_id'] as int?,
      name: json['name'] as String? ?? json['user_name'] as String? ?? 'User',
      email: json['email'] as String? ?? '',
      role: normalizeRole(json['role'] as String?),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'email': email,
        'role': role,
      };
}

class AuthState {
  final bool isLoading;
  final AuthUser? user;
  final String? errorMessage;
  final bool isAuthenticated;

  const AuthState({
    this.isLoading = false,
    this.user,
    this.errorMessage,
    this.isAuthenticated = false,
  });

  AuthUser? get currentUser => user;
  String? get currentRole => user?.role;

  AuthState copyWith({
    bool? isLoading,
    AuthUser? user,
    String? errorMessage,
    bool? isAuthenticated,
  }) {
    return AuthState(
      isLoading: isLoading ?? this.isLoading,
      user: user ?? this.user,
      errorMessage: errorMessage,
      isAuthenticated: isAuthenticated ?? this.isAuthenticated,
    );
  }
}

class AuthNotifier extends Notifier<AuthState> {
  late final ApiClient _api;
  late final SecureStorageService _storage;

  @override
  AuthState build() {
    _api = ref.watch(apiClientProvider);
    _storage = ref.watch(secureStorageProvider);
    _api.setOnUnauthorized(() => handleSessionExpired());
    Future.microtask(() => checkSession());
    return const AuthState(isLoading: false);
  }

  /// App restart and session restoration:
  /// Verifies token and resolves the authoritative backend role from /api/auth/me.
  /// If session is expired (401), clears credentials and redirects to login.
  Future<bool> checkSession() async {
    final token = await _storage.getToken();
    if (token == null || token.isEmpty) {
      state = const AuthState(isAuthenticated: false, user: null, isLoading: false);
      return false;
    }


    try {
      // 1. Authoritative backend role resolution
      final res = await _api.get(ApiEndpoints.me);
      final data = res.data as Map<String, dynamic>;
      final user = AuthUser.fromJson(data);

      await _storage.saveUser(jsonEncode(user.toJson()));
      state = AuthState(
        isAuthenticated: true,
        user: user,
        isLoading: false,
      );
      return true;
    } catch (e) {
      // Expired / invalid session or deactivated user
      if (e is UnauthorizedException ||
          e.toString().contains('401') ||
          e.toString().contains('Unauthorized') ||
          e.toString().contains('deactivated')) {
        await logout();
        return false;
      }

      // Offline / network failure fallback: restore cached session if available
      final userRaw = await _storage.getUser();
      if (userRaw != null && userRaw.isNotEmpty) {
        try {
          final cachedUser = AuthUser.fromJson(jsonDecode(userRaw) as Map<String, dynamic>);
          state = AuthState(
            isAuthenticated: true,
            user: cachedUser,
            isLoading: false,
          );
          return true;
        } catch (_) {
          await logout();
          return false;
        }
      }

      await logout();
      return false;
    }
  }

  /// Authenticate with backend credentials:
  /// JWT/session -> fetch authenticated user -> resolve backend role -> store role in session state
  Future<bool> login(String email, String password) async {
    state = state.copyWith(isLoading: true, errorMessage: null);
    try {
      // 1. Authenticate with backend
      final res = await _api.post(
        ApiEndpoints.login,
        data: {
          'email': email.trim().toLowerCase(),
          'password': password,
        },
      );
      final data = res.data as Map<String, dynamic>;
      final token = data['access_token'] as String;

      // 2. Save token
      await _storage.saveToken(token);

      // 3. Fetch authenticated user from backend session endpoint
      // Backend remains the single source of truth for the role
      final meRes = await _api.get(ApiEndpoints.me);
      final meData = meRes.data as Map<String, dynamic>;

      // 4. Resolve backend role
      final user = AuthUser.fromJson(meData);

      // 5. Store role and user in existing session state & secure storage
      await _storage.saveUser(jsonEncode(user.toJson()));

      state = AuthState(
        isAuthenticated: true,
        user: user,
        isLoading: false,
      );
      return true;
    } catch (e) {
      await _storage.clearAll();
      state = state.copyWith(
        isLoading: false,
        errorMessage: e.toString().replaceAll('Exception:', '').trim(),
      );
      return false;
    }
  }

  /// Register new user:
  /// Backend returns token and registers user; backend role is resolved via /api/auth/me
  Future<bool> register({
    required String name,
    required String email,
    required String password,
    required String role,
  }) async {
    state = state.copyWith(isLoading: true, errorMessage: null);
    try {
      final res = await _api.post(
        ApiEndpoints.register,
        data: {
          'name': name.trim(),
          'email': email.trim().toLowerCase(),
          'password': password,
          'role': role,
        },
      );
      final data = res.data as Map<String, dynamic>;
      final token = data['access_token'] as String;

      await _storage.saveToken(token);

      // Resolve authoritative backend role
      final meRes = await _api.get(ApiEndpoints.me);
      final meData = meRes.data as Map<String, dynamic>;
      final user = AuthUser.fromJson(meData);

      await _storage.saveUser(jsonEncode(user.toJson()));

      state = AuthState(
        isAuthenticated: true,
        user: user,
        isLoading: false,
      );
      return true;
    } catch (e) {
      await _storage.clearAll();
      state = state.copyWith(
        isLoading: false,
        errorMessage: e.toString().replaceAll('Exception:', '').trim(),
      );
      return false;
    }
  }

  Future<String?> forgotPassword(String email) async {
    state = state.copyWith(isLoading: true, errorMessage: null);
    try {
      final res = await _api.post(
        ApiEndpoints.forgotPassword,
        data: {'email': email.trim().toLowerCase()},
      );
      final data = res.data as Map<String, dynamic>;
      state = state.copyWith(isLoading: false);
      return data['demo_otp'] as String?;
    } catch (e) {
      final msg = e.toString().replaceAll('Exception:', '').trim();
      // Surface rate-limit (429) and delivery (503) errors to the UI
      state = state.copyWith(
        isLoading: false,
        errorMessage: msg,
      );
      return null;
    }
  }

  Future<bool> verifyOtp({
    required String email,
    required String otp,
  }) async {
    state = state.copyWith(isLoading: true, errorMessage: null);
    try {
      await _api.post(
        ApiEndpoints.verifyOtp,
        data: {
          'email': email.trim().toLowerCase(),
          'otp': otp.trim(),
        },
      );
      state = state.copyWith(isLoading: false);
      return true;
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        errorMessage: e.toString().replaceAll('Exception:', '').trim(),
      );
      return false;
    }
  }

  Future<bool> resetPassword({
    required String email,
    required String otpCode,
    required String newPassword,
  }) async {
    state = state.copyWith(isLoading: true, errorMessage: null);
    try {
      await _api.post(
        ApiEndpoints.resetPassword,
        data: {
          'email': email.trim().toLowerCase(),
          'otp_code': otpCode.trim(),
          'new_password': newPassword,
        },
      );
      state = state.copyWith(isLoading: false);
      return true;
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        errorMessage: e.toString().replaceAll('Exception:', '').trim(),
      );
      return false;
    }
  }

  /// On logout: clear token, session, current user, and role state.
  Future<void> logout() async {
    await _storage.deleteToken();
    await _storage.deleteUser();
    await _storage.clearAll();
    state = const AuthState(
      isAuthenticated: false,
      user: null,
      isLoading: false,
      errorMessage: null,
    );
  }

  /// Handles 401 session expiration by clearing all credentials and returning to login
  Future<void> handleSessionExpired() async {
    await logout();
  }
}

final authProvider = NotifierProvider<AuthNotifier, AuthState>(AuthNotifier.new);

final currentUserProvider = Provider<AuthUser?>((ref) {
  return ref.watch(authProvider).user;
});
