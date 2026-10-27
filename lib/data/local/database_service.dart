import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:sqflite_common_ffi_web/sqflite_ffi_web.dart';
import '../models/profile.dart';
import '../models/contact.dart';
import '../models/conversation.dart';
import '../models/message.dart';
import '../models/group.dart';

class DatabaseService {
  Database? _db;

  Future<Database> get database async {
    if (_db != null) return _db!;
    _db = await _initDatabase();
    return _db!;
  }

  Future<Database> _initDatabase() async {
    if (kIsWeb) {
      databaseFactory = databaseFactoryFfiWeb;
    } else if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    }

    String path;
    if (kIsWeb) {
      path = 'bharosa_vault.db';
    } else {
      final documentsDirectory = await getApplicationDocumentsDirectory();
      path = join(documentsDirectory.path, 'bharosa_vault.db');
    }

    return await openDatabase(
      path,
      version: 2,
      onCreate: _createTables,
      onUpgrade: (db, oldVersion, newVersion) async {
        await _createTables(db, newVersion);
      },
      onOpen: (db) async {
        await _createTables(db, 2);
        try {
          await db.execute("ALTER TABLE contacts ADD COLUMN requestStatus TEXT NOT NULL DEFAULT 'approved'");
        } catch (_) {}
        try {
          await db.execute("ALTER TABLE conversations ADD COLUMN requestStatus TEXT NOT NULL DEFAULT 'approved'");
        } catch (_) {}
      },
    );
  }

  Future<void> _createTables(Database db, int version) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS profiles (
        id TEXT PRIMARY KEY,
        displayName TEXT NOT NULL,
        photoPath TEXT,
        isIncognito INTEGER NOT NULL DEFAULT 0,
        isHidden INTEGER NOT NULL DEFAULT 0,
        createdAt INTEGER NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS contacts (
        id TEXT PRIMARY KEY,
        profileId TEXT NOT NULL,
        displayName TEXT NOT NULL,
        avatarUrl TEXT,
        isVerified INTEGER NOT NULL DEFAULT 0,
        securityCode TEXT NOT NULL,
        sendQueueId TEXT NOT NULL,
        receiveQueueId TEXT NOT NULL,
        peerPublicKey TEXT NOT NULL,
        ratchetStateJson TEXT,
        disappearingDurationSeconds INTEGER NOT NULL DEFAULT 0,
        isMuted INTEGER NOT NULL DEFAULT 0,
        isBlocked INTEGER NOT NULL DEFAULT 0,
        isReusableAddress INTEGER NOT NULL DEFAULT 0,
        requestStatus TEXT NOT NULL DEFAULT 'approved',
        createdAt INTEGER NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS conversations (
        id TEXT PRIMARY KEY,
        type TEXT NOT NULL,
        title TEXT NOT NULL,
        avatarUrl TEXT,
        lastMessageText TEXT,
        lastMessageTime INTEGER,
        unreadCount INTEGER NOT NULL DEFAULT 0,
        isMuted INTEGER NOT NULL DEFAULT 0,
        isArchived INTEGER NOT NULL DEFAULT 0,
        disappearingDurationSeconds INTEGER NOT NULL DEFAULT 0,
        draftText TEXT,
        contactId TEXT,
        groupId TEXT,
        isVerified INTEGER NOT NULL DEFAULT 0,
        requestStatus TEXT NOT NULL DEFAULT 'approved'
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS messages (
        id TEXT PRIMARY KEY,
        conversationId TEXT NOT NULL,
        senderId TEXT NOT NULL,
        senderName TEXT NOT NULL,
        type TEXT NOT NULL,
        content TEXT NOT NULL,
        filePath TEXT,
        fileName TEXT,
        fileSize INTEGER,
        mediaDurationMs INTEGER,
        status TEXT NOT NULL,
        timestamp INTEGER NOT NULL,
        expiresAt INTEGER,
        replyToId TEXT,
        replyToText TEXT,
        replyToSender TEXT,
        isEdited INTEGER NOT NULL DEFAULT 0,
        editHistory TEXT,
        isDeleted INTEGER NOT NULL DEFAULT 0,
        isSavedNote INTEGER NOT NULL DEFAULT 0
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS reactions (
        id TEXT PRIMARY KEY,
        messageId TEXT NOT NULL,
        contactId TEXT NOT NULL,
        emoji TEXT NOT NULL,
        timestamp INTEGER NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS groups (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        avatar TEXT,
        myRole TEXT NOT NULL,
        inviteLink TEXT NOT NULL,
        createdAt INTEGER NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS group_members (
        groupId TEXT NOT NULL,
        contactId TEXT NOT NULL,
        displayName TEXT NOT NULL,
        role TEXT NOT NULL,
        joinedAt INTEGER NOT NULL,
        PRIMARY KEY (groupId, contactId)
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS settings (
        key TEXT PRIMARY KEY,
        value TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS media_chunks (
        messageId TEXT NOT NULL,
        chunkIndex INTEGER NOT NULL,
        totalChunks INTEGER NOT NULL,
        chunkData TEXT NOT NULL,
        fileName TEXT,
        PRIMARY KEY (messageId, chunkIndex)
      )
    ''');

    // Create indexes for high performance querying
    await db.execute('CREATE INDEX IF NOT EXISTS idx_messages_conv ON messages(conversationId, timestamp)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_messages_expires ON messages(expiresAt)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_contacts_receive_queue ON contacts(receiveQueueId)');
  }

  // --- Media Chunks Persistence ---
  Future<void> saveMediaChunk({
    required String messageId,
    required int chunkIndex,
    required int totalChunks,
    required String chunkData,
    String? fileName,
  }) async {
    final db = await database;
    await db.insert(
      'media_chunks',
      {
        'messageId': messageId,
        'chunkIndex': chunkIndex,
        'totalChunks': totalChunks,
        'chunkData': chunkData,
        'fileName': fileName,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<int> getMediaChunkCount(String messageId) async {
    final db = await database;
    final res = await db.rawQuery(
      'SELECT COUNT(*) as cnt FROM media_chunks WHERE messageId = ?',
      [messageId],
    );
    return res.isNotEmpty ? (res.first['cnt'] as int? ?? 0) : 0;
  }

  Future<List<Map<String, dynamic>>> getMediaChunks(String messageId) async {
    final db = await database;
    return await db.query(
      'media_chunks',
      where: 'messageId = ?',
      whereArgs: [messageId],
      orderBy: 'chunkIndex ASC',
    );
  }

  Future<void> deleteMediaChunks(String messageId) async {
    final db = await database;
    await db.delete('media_chunks', where: 'messageId = ?', whereArgs: [messageId]);
  }

  // --- Profiles ---
  Future<void> saveProfile(Profile profile) async {
    final db = await database;
    await db.insert('profiles', profile.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<Profile?> getProfile(String id) async {
    final db = await database;
    final res = await db.query('profiles', where: 'id = ?', whereArgs: [id]);
    return res.isNotEmpty ? Profile.fromMap(res.first) : null;
  }

  Future<List<Profile>> getAllProfiles() async {
    final db = await database;
    final res = await db.query('profiles', orderBy: 'createdAt ASC');
    return res.map((m) => Profile.fromMap(m)).toList();
  }

  // --- Contacts ---
  Future<void> saveContact(Contact contact) async {
    final db = await database;
    await db.insert('contacts', contact.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<Contact?> getContact(String id) async {
    final db = await database;
    final res = await db.query('contacts', where: 'id = ?', whereArgs: [id]);
    return res.isNotEmpty ? Contact.fromMap(res.first) : null;
  }

  Future<Contact?> getContactByReceiveQueue(String queueId) async {
    final db = await database;
    final res = await db.query('contacts', where: 'receiveQueueId = ?', whereArgs: [queueId]);
    return res.isNotEmpty ? Contact.fromMap(res.first) : null;
  }

  Future<Contact?> getContactByPeerKey(String peerPublicKey) async {
    final db = await database;
    final res = await db.query('contacts', where: 'peerPublicKey = ?', whereArgs: [peerPublicKey]);
    return res.isNotEmpty ? Contact.fromMap(res.first) : null;
  }

  Future<Contact?> getContactBySendQueue(String sendQueueId) async {
    final db = await database;
    final res = await db.query('contacts', where: 'sendQueueId = ?', whereArgs: [sendQueueId]);
    return res.isNotEmpty ? Contact.fromMap(res.first) : null;
  }

  Future<List<Contact>> getAllContacts() async {
    final db = await database;
    final res = await db.query('contacts', orderBy: 'displayName ASC');
    return res.map((m) => Contact.fromMap(m)).toList();
  }

  Future<List<Contact>> getBlockedContacts() async {
    final db = await database;
    final res = await db.query(
      'contacts',
      where: "isBlocked = 1 OR requestStatus = 'blocked'",
      orderBy: 'displayName ASC',
    );
    return res.map((m) => Contact.fromMap(m)).toList();
  }

  Future<void> approveContact(String contactId) async {
    final db = await database;
    await db.update('contacts', {'requestStatus': 'approved', 'isBlocked': 0}, where: 'id = ?', whereArgs: [contactId]);
    await db.update('conversations', {'requestStatus': 'approved'}, where: 'id = ?', whereArgs: [contactId]);
  }

  Future<void> blockContact(String contactId) async {
    final db = await database;
    await db.update('contacts', {'requestStatus': 'blocked', 'isBlocked': 1}, where: 'id = ?', whereArgs: [contactId]);
    await db.update('conversations', {'requestStatus': 'blocked'}, where: 'id = ?', whereArgs: [contactId]);
  }

  Future<void> unblockContact(String contactId) async {
    final db = await database;
    await db.update('contacts', {'requestStatus': 'approved', 'isBlocked': 0}, where: 'id = ?', whereArgs: [contactId]);
    await db.update('conversations', {'requestStatus': 'approved'}, where: 'id = ?', whereArgs: [contactId]);
  }

  Future<void> deleteContact(String id) async {
    final db = await database;
    await db.delete('contacts', where: 'id = ?', whereArgs: [id]);
  }

  // --- Conversations ---
  Future<void> saveConversation(Conversation conv) async {
    final db = await database;
    await db.insert('conversations', conv.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<Conversation?> getConversation(String id) async {
    final db = await database;
    final res = await db.query('conversations', where: 'id = ?', whereArgs: [id]);
    return res.isNotEmpty ? Conversation.fromMap(res.first) : null;
  }

  Future<List<Conversation>> getConversations({bool includeArchived = false}) async {
    final db = await database;
    const baseClause = "requestStatus != 'pending_incoming' AND requestStatus != 'blocked'";
    final whereClause = includeArchived ? baseClause : "$baseClause AND isArchived = 0";
    final res = await db.query(
      'conversations',
      where: whereClause,
      orderBy: 'lastMessageTime DESC, id DESC',
    );
    return res.map((m) => Conversation.fromMap(m)).toList();
  }

  Future<List<Conversation>> getPendingRequests() async {
    final db = await database;
    final res = await db.query(
      'conversations',
      where: "requestStatus = 'pending_incoming'",
      orderBy: 'lastMessageTime DESC, id DESC',
    );
    return res.map((m) => Conversation.fromMap(m)).toList();
  }

  Future<int> getPendingRequestsCount() async {
    final db = await database;
    final res = await db.rawQuery("SELECT COUNT(*) as cnt FROM conversations WHERE requestStatus = 'pending_incoming'");
    return res.isNotEmpty ? (res.first['cnt'] as int? ?? 0) : 0;
  }

  Future<int> getSentMessagesCount(String conversationId) async {
    final db = await database;
    final res = await db.rawQuery("SELECT COUNT(*) as cnt FROM messages WHERE conversationId = ? AND senderId = 'self'", [conversationId]);
    return res.isNotEmpty ? (res.first['cnt'] as int? ?? 0) : 0;
  }



  Future<void> updateConversationDraft(String id, String? draftText) async {
    final db = await database;
    await db.update(
      'conversations',
      {'draftText': draftText},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> markConversationRead(String id) async {
    final db = await database;
    await db.update(
      'conversations',
      {'unreadCount': 0},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> setConversationMuted(String id, bool muted) async {
    final db = await database;
    await db.update(
      'conversations',
      {'isMuted': muted ? 1 : 0},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> setConversationArchived(String id, bool archived) async {
    final db = await database;
    await db.update(
      'conversations',
      {'isArchived': archived ? 1 : 0},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  // --- Messages ---
  Future<void> saveMessage(Message message) async {
    final db = await database;
    await db.insert('messages', message.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<Message?> getMessage(String id) async {
    final db = await database;
    final res = await db.query('messages', where: 'id = ?', whereArgs: [id]);
    return res.isNotEmpty ? Message.fromMap(res.first) : null;
  }

  Future<List<Message>> getMessages(String conversationId, {int limit = 100, int offset = 0}) async {
    final db = await database;
    final res = await db.query(
      'messages',
      where: 'conversationId = ? AND isDeleted = 0',
      whereArgs: [conversationId],
      orderBy: 'timestamp ASC',
      limit: limit,
      offset: offset,
    );
    return res.map((m) => Message.fromMap(m)).toList();
  }

  Future<void> updateMessageStatus(String messageId, MessageStatus status) async {
    final db = await database;
    await db.update(
      'messages',
      {'status': status.name},
      where: 'id = ?',
      whereArgs: [messageId],
    );
  }

  Future<void> deleteMessageForMe(String messageId) async {
    final db = await database;
    await db.update(
      'messages',
      {'isDeleted': 1},
      where: 'id = ?',
      whereArgs: [messageId],
    );
  }

  /// Purges messages whose disappearing timer has expired
  Future<int> purgeExpiredMessages() async {
    final db = await database;
    final now = DateTime.now().millisecondsSinceEpoch;
    return await db.delete(
      'messages',
      where: 'expiresAt IS NOT NULL AND expiresAt > 0 AND expiresAt <= ?',
      whereArgs: [now],
    );
  }

  // --- Reactions ---
  Future<void> saveReaction(Reaction reaction) async {
    final db = await database;
    await db.insert('reactions', reaction.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<List<Reaction>> getReactionsForMessage(String messageId) async {
    final db = await database;
    final res = await db.query('reactions', where: 'messageId = ?', whereArgs: [messageId]);
    return res.map((m) => Reaction.fromMap(m)).toList();
  }

  Future<void> removeReaction(String messageId, String contactId) async {
    final db = await database;
    await db.delete(
      'reactions',
      where: 'messageId = ? AND contactId = ?',
      whereArgs: [messageId, contactId],
    );
  }

  // --- Groups ---
  Future<void> saveGroup(Group group) async {
    final db = await database;
    await db.insert('groups', group.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<Group?> getGroup(String id) async {
    final db = await database;
    final res = await db.query('groups', where: 'id = ?', whereArgs: [id]);
    return res.isNotEmpty ? Group.fromMap(res.first) : null;
  }

  Future<List<Group>> getAllGroups() async {
    final db = await database;
    final res = await db.query('groups', orderBy: 'createdAt DESC');
    return res.map((m) => Group.fromMap(m)).toList();
  }

  Future<void> addGroupMember(GroupMember member) async {
    final db = await database;
    await db.insert('group_members', member.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<List<GroupMember>> getGroupMembers(String groupId) async {
    final db = await database;
    final res = await db.query('group_members', where: 'groupId = ?', whereArgs: [groupId]);
    return res.map((m) => GroupMember.fromMap(m)).toList();
  }

  // --- Local Search (Section 10 Phase 2: Chat search local) ---
  Future<List<Message>> searchMessages(String query) async {
    if (query.trim().isEmpty) return [];
    final db = await database;
    final res = await db.query(
      'messages',
      where: 'content LIKE ? AND isDeleted = 0',
      whereArgs: ['%$query%'],
      orderBy: 'timestamp DESC',
      limit: 50,
    );
    return res.map((m) => Message.fromMap(m)).toList();
  }

  /// Wipes all local tables
  Future<void> clearAll() async {
    final db = await database;
    await db.delete('messages');
    await db.delete('reactions');
    await db.delete('conversations');
    await db.delete('contacts');
    await db.delete('profiles');
    await db.delete('groups');
    await db.delete('group_members');
    await db.delete('settings');
  }

  /// Exports all database tables to a structured map for encrypted backup
  Future<Map<String, dynamic>> exportAllData() async {
    final db = await database;
    const tables = ['profiles', 'contacts', 'conversations', 'messages', 'groups', 'group_members', 'settings'];
    final result = <String, dynamic>{};
    for (final table in tables) {
      try {
        final rows = await db.query(table);
        result[table] = rows;
      } catch (_) {}
    }
    return result;
  }

  /// Restores all database tables from a structured map
  Future<void> importAllData(Map<String, dynamic> data) async {
    final db = await database;
    const tables = ['profiles', 'contacts', 'conversations', 'messages', 'groups', 'group_members', 'settings'];
    await db.transaction((txn) async {
      for (final table in tables) {
        if (data.containsKey(table) && data[table] is List) {
          final rows = data[table] as List;
          for (final row in rows) {
            if (row is Map<String, dynamic>) {
              await txn.insert(table, row, conflictAlgorithm: ConflictAlgorithm.replace);
            }
          }
        }
      }
    });
  }
}
