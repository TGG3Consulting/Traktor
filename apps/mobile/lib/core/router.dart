import 'package:go_router/go_router.dart';
import '../features/onboarding/splash_screen.dart';
import '../features/onboarding/language_screen.dart';
import '../features/onboarding/role_screen.dart';
import '../features/auth/phone_screen.dart';
import '../features/auth/otp_screen.dart';
import '../features/auth/profile_setup_screen.dart';
import '../features/home/home_shell.dart';

/// Маршруты приложения (go_router). Deep links (/job/{id}, /auction/{id},
/// /profile/{id}) добавляются вместе с соответствующими экранами.
final appRouter = GoRouter(
  initialLocation: '/',
  routes: [
    GoRoute(path: '/', builder: (_, __) => const SplashScreen()),
    GoRoute(path: '/onboarding/language', builder: (_, __) => const LanguageScreen()),
    GoRoute(path: '/onboarding/role', builder: (_, __) => const RoleScreen()),
    GoRoute(path: '/auth/phone', builder: (_, __) => const PhoneScreen()),
    GoRoute(path: '/auth/otp', builder: (_, __) => const OtpScreen()),
    GoRoute(path: '/auth/profile', builder: (_, __) => const ProfileSetupScreen()),
    GoRoute(path: '/home', builder: (_, __) => const HomeShell()),
  ],
);
