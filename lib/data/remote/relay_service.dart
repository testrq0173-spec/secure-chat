import 'dart:async';
import 'package:uuid/uuid.dart';

/// Unilateral Queue Packet payload
class QueuePacket {
  final String packetId;
  final String queueId;
  final String encryptedPayload; // Base64 outer ciphertext
  final int timestamp;
  final int size;

  QueuePacket({
    required this.packetId,
    required this.queueId,
    required this.encryptedPayload,
    required this.timestamp,
    required this.size,
  });

  Map<String, dynamic> toMap() => {
    'packetId': packetId,
    'queueId': queueId,
    'encryptedPayload': encryptedPayload,
    'timestamp': timestamp,
    'size': size,
  };

  factory QueuePacket.fromMap(Map<String, dynamic> map) => QueuePacket(
    packetId: map['packetId'] as String,
    queueId: map['queueId'] as String,
    encryptedPayload: map['encryptedPayload'] as String,
    timestamp: map['timestamp'] as int,
    size: map['size'] as int? ?? (map['encryptedPayload'] as String).length,
  );
}

/// Abstract Relay Service interface for Blinded Postbox
abstract class IRelayService {
  /// Registers a capability queue with an owner public key
  Future<void> registerQueue({
    required String queueId,
    required String ownerPublicKey,
    String? fcmToken,
  });

  /// Deposits an encrypted packet into the recipient's unilateral queue
  Future<void> depositPacket({
    required String queueId,
    required String encryptedPayload,
  });

  /// Fetches undelivered packets from the user's receiving queue
  Future<List<QueuePacket>> fetchPackets(String queueId);

  /// Acknowledges and immediately deletes a received packet from the relay
  Future<void> deletePacket({
    required String queueId,
    required String packetId,
  });

  /// Publishes a one-time connection invite
  Future<void> publishInvite({
    required String inviteId,
    required Map<String, dynamic> inviteData,
  });

  /// Fetches a one-time connection invite
  Future<Map<String, dynamic>?> fetchInvite(String inviteId);

  /// Consumes and deletes a one-time connection invite
  Future<void> consumeInvite(String inviteId);

  /// Stream of new incoming packets for real-time reactivity
  Stream<QueuePacket> listenToQueue(String queueId);
}

/// In-memory & reactive Blinded Relay Postbox implementation.
/// Adheres strictly to zero-knowledge postbox model with instant packet deletion.
class LocalBlindedRelayService implements IRelayService {
  static final LocalBlindedRelayService _instance = LocalBlindedRelayService._internal();
  factory LocalBlindedRelayService() => _instance;
  LocalBlindedRelayService._internal();

  final Map<String, List<QueuePacket>> _queues = {};
  final Map<String, Map<String, dynamic>> _invites = {};
  final Map<String, StreamController<QueuePacket>> _streamControllers = {};
  final _uuid = const Uuid();

  @override
  Future<void> registerQueue({
    required String queueId,
    required String ownerPublicKey,
    String? fcmToken,
  }) async {
    _queues.putIfAbsent(queueId, () => []);
    _streamControllers.putIfAbsent(queueId, () => StreamController<QueuePacket>.broadcast());
  }

  @override
  Future<void> depositPacket({
    required String queueId,
    required String encryptedPayload,
  }) async {
    final packet = QueuePacket(
      packetId: _uuid.v4(),
      queueId: queueId,
      encryptedPayload: encryptedPayload,
      timestamp: DateTime.now().millisecondsSinceEpoch,
      size: encryptedPayload.length,
    );

    _queues.putIfAbsent(queueId, () => []).add(packet);

    if (_streamControllers.containsKey(queueId)) {
      _streamControllers[queueId]!.add(packet);
    }
  }

  @override
  Future<List<QueuePacket>> fetchPackets(String queueId) async {
    return List.from(_queues[queueId] ?? []);
  }

  @override
  Future<void> deletePacket({
    required String queueId,
    required String packetId,
  }) async {
    _queues[queueId]?.removeWhere((p) => p.packetId == packetId);
  }

  @override
  Future<void> publishInvite({
    required String inviteId,
    required Map<String, dynamic> inviteData,
  }) async {
    _invites[inviteId] = Map.from(inviteData);
  }

  @override
  Future<Map<String, dynamic>?> fetchInvite(String inviteId) async {
    return _invites[inviteId];
  }

  @override
  Future<void> consumeInvite(String inviteId) async {
    _invites.remove(inviteId);
  }

  @override
  Stream<QueuePacket> listenToQueue(String queueId) {
    _streamControllers.putIfAbsent(queueId, () => StreamController<QueuePacket>.broadcast());
    return _streamControllers[queueId]!.stream;
  }
}
