import 'dart:convert';
import 'dart:typed_data';
import 'crypto_utils.dart';

/// Generates human-verifiable security codes (safety numbers) and QR payloads
class SafetyNumber {
  SafetyNumber._();

  /// Computes a deterministic 6-digit security code from two mutual public keys
  static String computeNumericCode(Uint8List keyA, Uint8List keyB) {
    // Sort keys lexicographically so both parties compute identical codes
    final hexA = CryptoUtils.toHex(keyA);
    final hexB = CryptoUtils.toHex(keyB);
    final sorted = (hexA.compareTo(hexB) < 0) ? hexA + hexB : hexB + hexA;

    final hash = CryptoUtils.sha256(CryptoUtils.utf8Bytes(sorted));
    final bd = ByteData.sublistView(hash);
    final num1 = bd.getUint32(0, Endian.big) % 1000;
    final num2 = bd.getUint32(4, Endian.big) % 1000;

    final part1 = num1.toString().padLeft(3, '0');
    final part2 = num2.toString().padLeft(3, '0');
    return '$part1 $part2';
  }

  /// Generates a payload for the verification QR comparison
  static String computeQrVerificationPayload({
    required Uint8List localPubKey,
    required Uint8List peerPubKey,
    required String connectionId,
  }) {
    final hexA = CryptoUtils.toHex(localPubKey);
    final hexB = CryptoUtils.toHex(peerPubKey);
    final sorted = (hexA.compareTo(hexB) < 0) ? '$hexA:$hexB' : '$hexB:$hexA';
    final payload = {
      'type': 'BHAROSA_VERIFY_SAFETY_NUMBER',
      'keys': sorted,
      'code': computeNumericCode(localPubKey, peerPubKey),
      'cid': connectionId,
    };
    return jsonEncode(payload);
  }
}
