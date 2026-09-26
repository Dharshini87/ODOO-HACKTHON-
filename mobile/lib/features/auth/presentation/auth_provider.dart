import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/providers/core_providers.dart';
import '../../../core/network/api_endpoints.dart';
import '../../../core/network/api_client.dart';
import '../../../core/storage/secure_storage.dart';

class AuthUser {
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
    };
    return !managerOnly.contains(permission.toLowerCase().trim());
  }

  factory AuthUser.fromJson(Map<String, dynamic> json) {
    return AuthUser(
      id: json['id'] as int? ?? json['user_id'] as int?,
      name: json['name'] as String? ?? json['user_name'] as String? ?? 'User',
      email: json['email'] as String? ?? '',
      role: json['role'] as String? ?? 'WAREHOUSE_STAFF',
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
    Future.microtask(() => checkSession());
    return const AuthState(isLoading: false);
  }

  Future<bool> checkSession() async {
    final token = await _storage.getToken();
    final userRaw = await _storage.getUser();

    if (token != null && token.isNotEmpty && userRaw != null) {
      try {
        final user = AuthUser.fromJson(jsonDecode(userRaw) as Map<String, dynamic>);
        state = AuthState(
          isAuthenticated: true,
          user: user,
          isLoading: false,
        );
        return true;
      } catch (_) {
        await _storage.clearAll();
      }
    }
    state = const AuthState(isAuthenticated: false, isLoading: false);
    return false;
  }

  Future<bool> login(String email, String password) async {
    state = state.copyWith(isLoading: true, errorMessage: null);
    try {
      final res = await _api.post(
        ApiEndpoints.login,
        data: {
          'email': email.trim().toLowerCase(),
          'password': password,
        },
      );
      final data = res.data as Map<String, dynamic>;
      final token = data['access_token'] as String;
      final userName = data['user_name'] as String? ?? 'User';
      final role = data['role'] as String? ?? 'WAREHOUSE_STAFF';
      final userId = data['user_id'] as int?;

      final user = AuthUser(
        id: userId,
        name: userName,
        email: email.trim().toLowerCase(),
        role: role,
      );
      await _storage.saveToken(token);
      await _storage.saveUser(jsonEncode(user.toJson()));

      state = AuthState(
        isAuthenticated: true,
        user: user,
        isLoading: false,
      );
      return true;
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        errorMessage: e.toString().replaceAll('Exception:', '').trim(),
      );
      return false;
    }
  }

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
      final userName = data['user_name'] as String? ?? name;
      final assignedRole = data['role'] as String? ?? role;
      final userId = data['user_id'] as int?;

      final user = AuthUser(
        id: userId,
        name: userName,
        email: email.trim().toLowerCase(),
        role: assignedRole,
      );
      await _storage.saveToken(token);
      await _storage.saveUser(jsonEncode(user.toJson()));

      state = AuthState(
        isAuthenticated: true,
        user: user,
        isLoading: false,
      );
      return true;
    } catch (e) {
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
      state = state.copyWith(
        isLoading: false,
        errorMessage: e.toString().replaceAll('Exception:', '').trim(),
      );
      return null;
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

  Future<void> logout() async {
    await _storage.clearAll();
    state = const AuthState(isAuthenticated: false, user: null, isLoading: false);
  }
}

final authProvider = NotifierProvider<AuthNotifier, AuthState>(AuthNotifier.new);
