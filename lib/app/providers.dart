import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/storage/secure_storage_service.dart';
import '../data/local/database_service.dart';
import '../data/models/conversation.dart';
import '../data/models/message.dart';
import '../data/models/profile.dart';
import '../data/remote/relay_service.dart';
import '../data/repositories/auth_repository.dart';
import '../data/repositories/chat_repository.dart';
import '../data/repositories/connection_repository.dart';

// --- Core Services ---
final secureStorageProvider = Provider<SecureStorageService>((ref) {
  return SecureStorageService();
});

final databaseServiceProvider = Provider<DatabaseService>((ref) {
  return DatabaseService();
});

final relayServiceProvider = Provider<IRelayService>((ref) {
  return HybridRelayService();
});

// --- Repositories ---
final authRepositoryProvider = Provider<AuthRepository>((ref) {
  return AuthRepository(
    secureStorage: ref.watch(secureStorageProvider),
    databaseService: ref.watch(databaseServiceProvider),
  );
});

final connectionRepositoryProvider = Provider<ConnectionRepository>((ref) {
  return ConnectionRepository(
    relayService: ref.watch(relayServiceProvider),
    databaseService: ref.watch(databaseServiceProvider),
    secureStorage: ref.watch(secureStorageProvider),
  );
});

final chatRepositoryProvider = Provider<ChatRepository>((ref) {
  final repo = ChatRepository(
    relayService: ref.watch(relayServiceProvider),
    databaseService: ref.watch(databaseServiceProvider),
    secureStorage: ref.watch(secureStorageProvider),
  );
  ref.onDispose(() => repo.dispose());
  return repo;
});

// --- Active Profile State ---
final activeProfileProvider = FutureProvider<Profile?>((ref) async {
  final authRepo = ref.watch(authRepositoryProvider);
  return await authRepo.getCurrentProfile();
});

// --- Conversations List Notifier (Riverpod 3 Notifier) ---
class ConversationsNotifier extends Notifier<AsyncValue<List<Conversation>>> {
  @override
  AsyncValue<List<Conversation>> build() {
    final chatRepo = ref.watch(chatRepositoryProvider);
    chatRepo.onIncomingMessage.listen((_) {
      loadConversations();
    });
    Future.microtask(() => loadConversations());
    return const AsyncValue.loading();
  }

  Future<void> loadConversations({bool includeArchived = false}) async {
    try {
      final db = ref.read(databaseServiceProvider);
      final list = await db.getConversations(includeArchived: includeArchived);
      state = AsyncValue.data(list);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  Future<void> toggleMute(String conversationId, bool currentMuted) async {
    final db = ref.read(databaseServiceProvider);
    await db.setConversationMuted(conversationId, !currentMuted);
    await loadConversations();
  }

  Future<void> toggleArchive(String conversationId, bool currentArchived) async {
    final db = ref.read(databaseServiceProvider);
    await db.setConversationArchived(conversationId, !currentArchived);
    await loadConversations();
  }
}

final conversationsProvider =
    NotifierProvider<ConversationsNotifier, AsyncValue<List<Conversation>>>(
  ConversationsNotifier.new,
);

// --- Chat Messages Notifier per Conversation ---
class ChatMessagesNotifier extends Notifier<AsyncValue<List<Message>>> {
  final String conversationId;
  ChatMessagesNotifier(this.conversationId);

  @override
  AsyncValue<List<Message>> build() {
    final chatRepo = ref.watch(chatRepositoryProvider);
    chatRepo.onIncomingMessage.listen((msg) {
      if (msg.conversationId == conversationId) {
        loadMessages();
      }
    });
    Future.microtask(() => loadMessages());
    return const AsyncValue.loading();
  }

  Future<void> loadMessages() async {
    try {
      final db = ref.read(databaseServiceProvider);
      await db.purgeExpiredMessages();
      final list = await db.getMessages(conversationId);
      state = AsyncValue.data(list);
      await db.markConversationRead(conversationId);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }
}

final chatMessagesProvider =
    NotifierProvider.family<ChatMessagesNotifier, AsyncValue<List<Message>>, String>(
  (arg) => ChatMessagesNotifier(arg),
);

// --- App Lock State ---
class AppLockState {
  final bool isLocked;
  final bool isPinSet;
  final bool isBiometricEnabled;
  final int lockTimeoutSeconds;

  AppLockState({
    required this.isLocked,
    required this.isPinSet,
    required this.isBiometricEnabled,
    required this.lockTimeoutSeconds,
  });

  AppLockState copyWith({
    bool? isLocked,
    bool? isPinSet,
    bool? isBiometricEnabled,
    int? lockTimeoutSeconds,
  }) {
    return AppLockState(
      isLocked: isLocked ?? this.isLocked,
      isPinSet: isPinSet ?? this.isPinSet,
      isBiometricEnabled: isBiometricEnabled ?? this.isBiometricEnabled,
      lockTimeoutSeconds: lockTimeoutSeconds ?? this.lockTimeoutSeconds,
    );
  }
}

class AppLockNotifier extends Notifier<AppLockState> {
  @override
  AppLockState build() {
    Future.microtask(() => refresh());
    return AppLockState(
      isLocked: false,
      isPinSet: false,
      isBiometricEnabled: false,
      lockTimeoutSeconds: 60,
    );
  }

  Future<void> refresh() async {
    final storage = ref.read(secureStorageProvider);
    final pinSet = await storage.isPinSet();
    final bio = await storage.isBiometricsEnabled();
    final timeout = await storage.getLockTimeout();
    state = state.copyWith(
      isLocked: pinSet,
      isPinSet: pinSet,
      isBiometricEnabled: bio,
      lockTimeoutSeconds: timeout,
    );
  }

  void unlock() {
    state = state.copyWith(isLocked: false);
  }

  void lock() {
    if (state.isPinSet) {
      state = state.copyWith(isLocked: true);
    }
  }

  Future<bool> verifyAndUnlock(String pin) async {
    final storage = ref.read(secureStorageProvider);
    final success = await storage.verifyAppPin(pin);
    if (success) {
      unlock();
    }
    return success;
  }
}

final appLockProvider = NotifierProvider<AppLockNotifier, AppLockState>(AppLockNotifier.new);
