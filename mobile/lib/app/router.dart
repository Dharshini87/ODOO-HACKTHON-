import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../features/auth/presentation/auth_provider.dart';
import '../features/auth/presentation/splash_screen.dart';
import '../features/auth/presentation/login_screen.dart';
import '../features/auth/presentation/register_screen.dart';
import '../features/auth/presentation/forgot_password_screen.dart';
import '../features/auth/presentation/otp_verification_screen.dart';
import '../features/auth/presentation/reset_password_screen.dart';
import '../features/dashboard/presentation/dashboard_screen.dart';
import '../features/operations/presentation/operations_screen.dart';
import '../features/stock/presentation/stock_screen.dart';
import '../features/move_history/presentation/history_screen.dart';
import '../features/more/presentation/more_screen.dart';
import 'scaffold_shell.dart';

final GlobalKey<NavigatorState> _rootNavigatorKey = GlobalKey<NavigatorState>(debugLabel: 'root');

final routerProvider = Provider<GoRouter>((ref) {
  final authState = ref.watch(authProvider);

  return GoRouter(
    navigatorKey: _rootNavigatorKey,
    initialLocation: '/splash',
    redirect: (context, state) {
      if (authState.isLoading) return null;

      final loc = state.matchedLocation;
      final isAuthFlow = loc == '/login' ||
          loc == '/register' ||
          loc == '/forgot-password' ||
          loc == '/otp-verification' ||
          loc == '/reset-password' ||
          loc == '/splash';
      final isLoggedIn = authState.isAuthenticated;

      if (!isLoggedIn && !isAuthFlow) {
        return '/login';
      }
      if (isLoggedIn && isAuthFlow && loc != '/splash') {
        return '/home';
      }
      return null;
    },
    routes: [
      GoRoute(
        path: '/splash',
        builder: (context, state) => const SplashScreen(),
      ),
      GoRoute(
        path: '/login',
        builder: (context, state) => const LoginScreen(),
      ),
      GoRoute(
        path: '/register',
        builder: (context, state) => const RegisterScreen(),
      ),
      GoRoute(
        path: '/forgot-password',
        builder: (context, state) => const ForgotPasswordScreen(),
      ),
      GoRoute(
        path: '/otp-verification',
        builder: (context, state) {
          final email = state.uri.queryParameters['email'] ?? '';
          return OtpVerificationScreen(email: email);
        },
      ),
      GoRoute(
        path: '/reset-password',
        builder: (context, state) {
          final email = state.uri.queryParameters['email'] ?? '';
          final otp = state.uri.queryParameters['otp'] ?? '';
          return ResetPasswordScreen(email: email, otpCode: otp);
        },
      ),
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) {
          return ScaffoldShell(navigationShell: navigationShell);
        },
        branches: [
          // 0. HOME
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/home',
                builder: (context, state) => const DashboardScreen(),
              ),
            ],
          ),
          // 1. OPERATIONS
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/operations',
                builder: (context, state) => const OperationsScreen(),
              ),
            ],
          ),
          // 2. STOCK
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/stock',
                builder: (context, state) => const StockScreen(),
              ),
            ],
          ),
          // 3. HISTORY
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/history',
                builder: (context, state) => const HistoryScreen(),
              ),
            ],
          ),
          // 4. MORE
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/more',
                builder: (context, state) => const MoreScreen(),
              ),
            ],
          ),
        ],
      ),
    ],
  );
});
