import 'package:go_router/go_router.dart';

import '../features/auth/otp_screen.dart';
import '../features/chat/chat_screen.dart';
import '../features/auth/phone_screen.dart';
import '../features/auth/profile_setup_screen.dart';
import '../features/home/home_shell.dart';
import '../features/jobs/create/published_screen.dart';
import '../features/jobs/create/step1_category.dart';
import '../features/jobs/create/step2_params.dart';
import '../features/jobs/create/step3_place.dart';
import '../features/jobs/create/step4_price.dart';
import '../features/jobs/create/step5_review.dart';
import '../features/jobs/auction/auction_screen.dart';
import '../features/jobs/deal/deal_screen.dart';
import '../features/jobs/job_detail_screen.dart';
import '../features/jobs/offers/offers_screen.dart';
import '../features/crm/business_screen.dart';
import '../features/complaints/complaint_queue_screen.dart';
import '../features/complaints/dashboard_screen.dart';
import '../features/disputes/dispute_queue_screen.dart';
import '../features/crm/calendar_screen.dart';
import '../features/crm/spending_screen.dart';
import '../features/equipment/equipment_list_screen.dart';
import '../features/equipment/equipment_new_screen.dart';
import '../features/equipment/equipment_wizard_screen.dart';
import '../features/moderation/catalog_screen.dart';
import '../features/moderation/moderation_screen.dart';
import '../features/moderation/user_card_screen.dart';
import '../features/moderation/verification_queue_screen.dart';
import '../features/moderation/users_screen.dart';
import '../features/notifications/settings_screen.dart';
import '../features/profile/delete_account_screen.dart';
import '../features/profile/public_profile_screen.dart';
import '../features/profile/verification_screen.dart';
import '../features/reviews/review_screen.dart';
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

    // Переписка (ТЗ §2.12). Список чатов живёт вкладкой домашнего экрана,
    // отдельная ветка — конкретный чат: на него ведут уведомления.
    GoRoute(
      path: '/chats/:id',
      builder: (_, state) => ChatScreen(chatId: state.pathParameters['id']!),
    ),

    // Аукцион (ТЗ §2.9) — лента торга и ставки.
    GoRoute(
      path: '/jobs/:id/bids',
      builder: (_, state) => AuctionScreen(jobId: state.pathParameters['id']!),
    ),

    // Сделка (ТЗ §2.11) — общий экран обеих сторон.
    GoRoute(
      path: '/deals/:id',
      builder: (_, state) => DealScreen(dealId: state.pathParameters['id']!),
    ),

    // Карточка человека (ТЗ §2.3): открыта без входа — ссылкой делятся.
    GoRoute(
      path: '/users/:id',
      builder: (_, state) => PublicProfileScreen(userId: state.pathParameters['id']!),
    ),

    // CRM исполнителя (ТЗ §3.1).
    GoRoute(path: '/crm/business', builder: (_, __) => const BusinessScreen()),
    GoRoute(path: '/crm/spending', builder: (_, __) => const SpendingScreen()),
    GoRoute(path: '/crm/calendar', builder: (_, __) => const CalendarScreen()),

    // Техника исполнителя (ТЗ §2.5): список и визард из четырёх шагов.
    GoRoute(path: '/equipment', builder: (_, __) => const EquipmentListScreen()),
    GoRoute(path: '/equipment/new', builder: (_, __) => const EquipmentNewScreen()),
    GoRoute(
      path: '/equipment/:id/edit/:step',
      builder: (_, state) => EquipmentWizardScreen(
        equipmentId: state.pathParameters['id']!,
        step: int.tryParse(state.pathParameters['step'] ?? '1') ?? 1,
      ),
    ),

    // Очередь споров (ТЗ §4.1) — доступна модерации.
    GoRoute(path: '/moderation/disputes', builder: (_, __) => const DisputeQueueScreen()),

    // Очередь жалоб на контент (ТЗ §4.1, п.6) — доступна модерации.
    GoRoute(path: '/moderation/complaints', builder: (_, __) => const ComplaintQueueScreen()),

    // Сводка площадки (ТЗ §4.1, п.1) — доступна модерации.
    GoRoute(path: '/moderation/dashboard', builder: (_, __) => const DashboardScreen()),

    // Проверка людей (ТЗ §2.3) — очередь модерации и подача документа.
    GoRoute(
      path: '/moderation/verifications',
      builder: (_, __) => const VerificationQueueScreen(),
    ),
    GoRoute(path: '/profile/verification', builder: (_, __) => const VerificationScreen()),
    GoRoute(path: '/profile/delete', builder: (_, __) => const DeleteAccountScreen()),

    // Справочник (ТЗ §4.1, п.5) — правка категорий без выката сервиса.
    GoRoute(path: '/moderation/catalog', builder: (_, __) => const CatalogEditScreen()),

    // Пользователи (ТЗ §4.1, п.3) — поиск, карточка, ограничения.
    GoRoute(path: '/moderation/users', builder: (_, __) => const AdminUsersScreen()),
    GoRoute(
      path: '/moderation/users/:id',
      builder: (_, state) => AdminUserCardScreen(userId: state.pathParameters['id']!),
    ),

    // Очередь проверки техники (ТЗ §4.1) — доступна модерации.
    GoRoute(path: '/moderation', builder: (_, __) => const ModerationScreen()),

    // Настройки уведомлений (ТЗ §2.14).
    GoRoute(
      path: '/settings/notifications',
      builder: (_, __) => const NotificationSettingsScreen(),
    ),

    // Взаимная оценка после сделки (ТЗ §2.13). Отдельный маршрут: на него
    // ведёт и кнопка со сделки, и уведомление «оставьте оценку».
    GoRoute(
      path: '/deals/:id/review',
      builder: (_, state) => ReviewScreen(dealId: state.pathParameters['id']!),
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
