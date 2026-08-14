import 'package:go_router/go_router.dart';

import '../features/auth/otp_screen.dart';
import '../features/auth/phone_screen.dart';
import '../features/auth/profile_setup_screen.dart';
import '../features/home/home_shell.dart';
import '../features/jobs/create/published_screen.dart';
import '../features/jobs/create/step1_category.dart';
import '../features/jobs/create/step2_params.dart';
import '../features/jobs/create/step3_place.dart';
import '../features/jobs/create/step4_price.dart';
import '../features/jobs/create/step5_review.dart';
import '../features/jobs/deal/deal_screen.dart';
import '../features/jobs/job_detail_screen.dart';
import '../features/jobs/offers/offers_screen.dart';
import '../features/onboarding/language_screen.dart';
import '../features/onboarding/role_screen.dart';
import '../features/onboarding/splash_screen.dart';

/// Маршруты приложения (go_router).
///
/// Шаги визарда — отдельные маршруты, а не страницы внутри одного экрана:
/// так работает кнопка «назад» в браузере и телефоне, а ссылка на конкретный
/// шаг переживает перезапуск.
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

    // Создание задания (ТЗ §2.6) — пять шагов.
    GoRoute(path: '/jobs/create/1', builder: (_, __) => const CreateStep1()),
    GoRoute(path: '/jobs/create/2', builder: (_, __) => const CreateStep2()),
    GoRoute(path: '/jobs/create/3', builder: (_, __) => const CreateStep3()),
    GoRoute(path: '/jobs/create/4', builder: (_, __) => const CreateStep4()),
    GoRoute(path: '/jobs/create/5', builder: (_, __) => const CreateStep5()),
    GoRoute(
      path: '/jobs/published/:id',
      builder: (_, state) => JobPublishedScreen(jobId: state.pathParameters['id']!),
    ),

    // Сделка (ТЗ §2.11) — общий экран обеих сторон.
    GoRoute(
      path: '/deals/:id',
      builder: (_, state) => DealScreen(dealId: state.pathParameters['id']!),
    ),

    // Отклики по заданию (ТЗ §2.10) — экран заказчика.
    GoRoute(
      path: '/jobs/:id/offers',
      builder: (_, state) => JobOffersScreen(jobId: state.pathParameters['id']!),
    ),

    // Деталка задания. Ссылка вида /jobs/{id} — то, чем делятся в мессенджере,
    // поэтому она открывается и без входа (гостевой просмотр).
    GoRoute(
      path: '/jobs/:id',
      builder: (_, state) => JobDetailScreen(jobId: state.pathParameters['id']!),
    ),
  ],
);
