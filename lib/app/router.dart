import 'package:go_router/go_router.dart';
import '../features/chats/chat_list_screen.dart';
import '../features/chats/chat_screen.dart';
import '../features/connect/new_connection_screen.dart';
import '../features/connect/security_code_screen.dart';
import '../features/groups/create_group_screen.dart';
import '../features/groups/group_info_screen.dart';
import '../features/profile/create_profile_screen.dart';
import '../features/onboarding/onboarding_screen.dart';
import '../features/onboarding/splash_screen.dart';
import '../features/security/lock_screen.dart';
import '../features/security/set_lock_screen.dart';
import '../features/settings/settings_screen.dart';

final appRouter = GoRouter(
  initialLocation: '/',
  routes: [
    GoRoute(
      path: '/',
      builder: (context, state) => const SplashScreen(),
    ),
    GoRoute(
      path: '/onboarding',
      builder: (context, state) => const OnboardingScreen(),
    ),
    GoRoute(
      path: '/create-profile',
      builder: (context, state) => const CreateProfileScreen(),
    ),
    GoRoute(
      path: '/set-lock',
      builder: (context, state) => const SetLockScreen(),
    ),
    GoRoute(
      path: '/lock',
      builder: (context, state) => const LockScreen(),
    ),
    GoRoute(
      path: '/home',
      builder: (context, state) => const ChatListScreen(),
    ),
    GoRoute(
      path: '/new-connection',
      builder: (context, state) => const NewConnectionScreen(),
    ),
    GoRoute(
      path: '/chat/:id',
      builder: (context, state) {
        final id = state.pathParameters['id']!;
        return ChatScreen(conversationId: id);
      },
    ),
    GoRoute(
      path: '/security-code/:id',
      builder: (context, state) {
        final id = state.pathParameters['id']!;
        return SecurityCodeScreen(contactId: id);
      },
    ),
    GoRoute(
      path: '/create-group',
      builder: (context, state) => const CreateGroupScreen(),
    ),
    GoRoute(
      path: '/group-info/:id',
      builder: (context, state) {
        final id = state.pathParameters['id']!;
        return GroupInfoScreen(groupId: id);
      },
    ),
    GoRoute(
      path: '/settings',
      builder: (context, state) => const SettingsScreen(),
    ),
  ],
);
