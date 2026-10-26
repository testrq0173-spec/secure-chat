import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:crypto/crypto.dart' as crypto;

/// Cryptographic utilities: CSPRNG, constant-time compare, padding buckets, serialization.
class CryptoUtils {
  CryptoUtils._();

  static final Random _secureRandom = Random.secure();

  /// Generates cryptographically secure random bytes
  static Uint8List randomBytes(int length) {
    final values = Uint8List(length);
    for (int i = 0; i < length; i++) {
      values[i] = _secureRandom.nextInt(256);
    }
    return values;
  }

  /// Generates a 128-bit (16-byte) or 256-bit URL-safe random string capability for queue IDs
  static String randomToken([int byteLength = 16]) {
    final bytes = randomBytes(byteLength);
    return base64UrlEncode(bytes).replaceAll('=', '');
  }

  /// Constant-time byte array equality to prevent timing attacks
  static bool constantTimeEquals(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    int result = 0;
    for (int i = 0; i < a.length; i++) {
      result |= a[i] ^ b[i];
    }
    return result == 0;
  }

  /// Standard SHA-256 hash
  static Uint8List sha256(List<int> input) {
    final digest = crypto.sha256.convert(input);
    return Uint8List.fromList(digest.bytes);
  }

  /// HMAC-SHA256
  static Uint8List hmacSha256(List<int> key, List<int> data) {
    final hmac = crypto.Hmac(crypto.sha256, key);
    final digest = hmac.convert(data);
    return Uint8List.fromList(digest.bytes);
  }

  /// HKDF-Extract and Expand using SHA-256
  static Uint8List hkdf({
    required List<int> ikm, // Input Key Material
    required List<int> salt,
    required List<int> info,
    required int length,
  }) {
    // 1. Extract: PRK = HMAC-Hash(salt, IKM)
    final actualSalt = salt.isEmpty ? Uint8List(32) : salt;
    final prk = hmacSha256(actualSalt, ikm);

    // 2. Expand: OKM = HMAC-Hash(PRK, info || 0x01) || ...
    final okm = <int>[];
    var previousT = <int>[];
    int counter = 1;

    while (okm.length < length) {
      final input = <int>[...previousT, ...info, counter];
      final t = hmacSha256(prk, input);
      okm.addAll(t);
      previousT = t;
      counter++;
    }

    return Uint8List.fromList(okm.sublist(0, length));
  }

  /// Bucket thresholds for message padding to resist traffic size correlation (Section 4.3)
  static const List<int> paddingBuckets = [128, 512, 2048, 8192, 32768, 65536];

  /// Pads message plaintext bytes to the nearest bucket size using length prefix + random padding
  static Uint8List padToBucket(Uint8List plaintext) {
    final originalLength = plaintext.length;
    int targetBucket = -1;
    for (final bucket in paddingBuckets) {
      if (originalLength + 4 <= bucket) {
        targetBucket = bucket;
        break;
      }
    }

    if (targetBucket == -1) {
      // For large media payloads > 64KB, pad to nearest 512 bytes
      final remainder = (originalLength + 4) % 512;
      targetBucket = remainder == 0 ? (originalLength + 4) : (originalLength + 4 + (512 - remainder));
    }

    // Allocate target bucket
    final padded = Uint8List(targetBucket);
    // First 4 bytes: big-endian original length
    final byteData = ByteData.sublistView(padded);
    byteData.setUint32(0, originalLength, Endian.big);

    // Copy original plaintext
    padded.setRange(4, 4 + originalLength, plaintext);

    // Fill the remainder with pseudorandom bytes (indistinguishable from ciphertext)
    final remainder = targetBucket - (4 + originalLength);
    if (remainder > 0) {
      final padBytes = randomBytes(remainder);
      padded.setRange(4 + originalLength, targetBucket, padBytes);
    }

    return padded;
  }

  /// Unpads a bucket-padded byte buffer back to original plaintext
  static Uint8List unpadFromBucket(Uint8List padded) {
    if (padded.length < 4) {
      throw const FormatException('Invalid padded buffer length');
    }
    final byteData = ByteData.sublistView(padded);
    final originalLength = byteData.getUint32(0, Endian.big);

    if (originalLength > padded.length - 4) {
      throw const FormatException('Corrupted length header in padded buffer');
    }

    return Uint8List.sublistView(padded, 4, 4 + originalLength);
  }

  /// Helper to convert string to UTF-8 bytes
  static Uint8List utf8Bytes(String text) => Uint8List.fromList(utf8.encode(text));

  /// Helper to convert bytes to UTF-8 string
  static String utf8String(List<int> bytes) => utf8.decode(bytes);

  /// Safe Hex encode
  static String toHex(List<int> bytes) {
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  /// Safe Hex decode
  static Uint8List fromHex(String hex) {
    final result = Uint8List(hex.length ~/ 2);
    for (int i = 0; i < hex.length; i += 2) {
      result[i ~/ 2] = int.parse(hex.substring(i, i + 2), radix: 16);
    }
    return result;
  }
}
