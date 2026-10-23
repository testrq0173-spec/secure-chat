import 'dart:convert';

class ConnectionInvite {
  final String inviteId;
  final String inviterDisplayName;
  final String inviterIdentityKey; // Base64 Ed25519 or identity key
  final String inviterDhKey; // Base64 X25519 ephemeral key
  final String inboxQueueId; // Unilateral queue for Bob to deliver his response
  final int expiresAt;
  final bool isReusable;

  ConnectionInvite({
    required this.inviteId,
    required this.inviterDisplayName,
    required this.inviterIdentityKey,
    required this.inviterDhKey,
    required this.inboxQueueId,
    required this.expiresAt,
    this.isReusable = false,
  });

  /// Encodes invite into a shareable URL and QR code payload
  /// Format: `bharosa://connect?data=<base64UrlJson>`
  String toDeepLink() {
    final jsonStr = jsonEncode(toJson());
    final encoded = base64UrlEncode(utf8.encode(jsonStr)).replaceAll('=', '');
    return 'bharosa://connect?data=$encoded';
  }

  /// Parses invite from deep link URL or raw QR text
  static ConnectionInvite? fromDeepLink(String input) {
    try {
      String dataParam = input.trim();
      if (input.contains('bharosa://connect?data=')) {
        dataParam = input.split('bharosa://connect?data=').last;
      } else if (input.contains('data=')) {
        dataParam = Uri.parse(input).queryParameters['data'] ?? '';
      }

      var normalized = dataParam;
      while (normalized.length % 4 != 0) {
        normalized += '=';
      }
      final decodedJson = utf8.decode(base64Url.decode(normalized));
      final map = jsonDecode(decodedJson) as Map<String, dynamic>;
      return ConnectionInvite.fromJson(map);
    } catch (_) {
      return null;
    }
  }

  Map<String, dynamic> toJson() => {
    'id': inviteId,
    'name': inviterDisplayName,
    'ik': inviterIdentityKey,
    'dh': inviterDhKey,
    'q': inboxQueueId,
    'exp': expiresAt,
    'reusable': isReusable,
  };

  factory ConnectionInvite.fromJson(Map<String, dynamic> json) => ConnectionInvite(
    inviteId: json['id'] as String,
    inviterDisplayName: json['name'] as String,
    inviterIdentityKey: json['ik'] as String,
    inviterDhKey: json['dh'] as String,
    inboxQueueId: json['q'] as String,
    expiresAt: json['exp'] as int,
    isReusable: json['reusable'] as bool? ?? false,
  );
}

/// Payload sent in the initial handshake packet from Bob back to Alice
class ConnectionHandshake {
  final String responderDisplayName;
  final String responderIdentityKey;
  final String responderDhKey;
  final String responderInboxQueueId;
  final String initialSecurityCode;

  ConnectionHandshake({
    required this.responderDisplayName,
    required this.responderIdentityKey,
    required this.responderDhKey,
    required this.responderInboxQueueId,
    required this.initialSecurityCode,
  });

  Map<String, dynamic> toJson() => {
    'name': responderDisplayName,
    'ik': responderIdentityKey,
    'dh': responderDhKey,
    'q': responderInboxQueueId,
    'code': initialSecurityCode,
  };

  factory ConnectionHandshake.fromJson(Map<String, dynamic> json) => ConnectionHandshake(
    responderDisplayName: json['name'] as String,
    responderIdentityKey: json['ik'] as String,
    responderDhKey: json['dh'] as String,
    responderInboxQueueId: json['q'] as String,
    initialSecurityCode: json['code'] as String,
  );
}
