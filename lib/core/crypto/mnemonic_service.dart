import 'dart:convert';
import 'dart:typed_data';
import 'package:crypto/crypto.dart' as crypto;
import 'package:cryptography/cryptography.dart';
import 'bip39_words.dart';
import 'crypto_utils.dart';

/// BIP-39 compliant mnemonic phrase generator, validator, and deterministic seed derivation.
class MnemonicService {
  MnemonicService._();

  static final Map<String, int> _wordMap = {
    for (int i = 0; i < bip39EnglishWords.length; i++) bip39EnglishWords[i]: i,
  };

  /// Generates a cryptographically random 12-word mnemonic phrase (128-bit entropy + 4-bit checksum)
  static String generateMnemonic() {
    // 1. Generate 16 bytes (128 bits) of cryptographic random entropy
    final entropy = CryptoUtils.randomBytes(16);

    // 2. Compute SHA-256 hash of entropy
    final hash = CryptoUtils.sha256(entropy);
    final checksumByte = hash[0]; // First 8 bits

    // 3. Build 132-bit bitstring (128 bits entropy + 4 bits checksum)
    final bits = <int>[];
    for (final byte in entropy) {
      for (int i = 7; i >= 0; i--) {
        bits.add((byte >> i) & 1);
      }
    }
    // Append top 4 bits of checksum
    for (int i = 7; i >= 4; i--) {
      bits.add((checksumByte >> i) & 1);
    }

    // 4. Split into 12 words of 11 bits each
    final words = <String>[];
    for (int i = 0; i < 12; i++) {
      int index = 0;
      for (int b = 0; b < 11; b++) {
        index = (index << 1) | bits[i * 11 + b];
      }
      words.add(bip39EnglishWords[index]);
    }

    return words.join(' ');
  }

  /// Validates a 12-word mnemonic phrase against BIP-39 wordlist and checksum
  static bool validateMnemonic(String phrase) {
    final words = phrase.trim().toLowerCase().split(RegExp(r'\s+'));
    if (words.length != 12) return false;

    final bits = <int>[];
    for (final word in words) {
      final index = _wordMap[word];
      if (index == null) return false;
      for (int i = 10; i >= 0; i--) {
        bits.add((index >> i) & 1);
      }
    }

    // First 128 bits = 16 bytes entropy
    final entropy = Uint8List(16);
    for (int i = 0; i < 16; i++) {
      int byte = 0;
      for (int b = 0; b < 8; b++) {
        byte = (byte << 1) | bits[i * 8 + b];
      }
      entropy[i] = byte;
    }

    // Expected checksum from entropy
    final hash = CryptoUtils.sha256(entropy);
    final expectedChecksum4Bits = (hash[0] >> 4) & 0x0F;

    // Actual checksum from last 4 bits
    int actualChecksum4Bits = 0;
    for (int b = 128; b < 132; b++) {
      actualChecksum4Bits = (actualChecksum4Bits << 1) | bits[b];
    }

    return expectedChecksum4Bits == actualChecksum4Bits;
  }

  /// Converts a mnemonic phrase to a 64-byte (512-bit) master seed using PBKDF2-HMAC-SHA512 (2048 rounds)
  static Uint8List mnemonicToSeed(String phrase, [String passphrase = '']) {
    final normalized = phrase.trim().toLowerCase().split(RegExp(r'\s+')).join(' ');
    final passwordBytes = utf8.encode(normalized);
    final saltBytes = utf8.encode('mnemonic$passphrase');

    // BIP-39 uses PBKDF2 with HMAC-SHA512, 2048 iterations, output length 64 bytes (1 block)
    final hmac = crypto.Hmac(crypto.sha512, passwordBytes);

    // Initial block input: salt || 0x00000001 (big endian 32-bit int 1)
    final blockInput = Uint8List(saltBytes.length + 4);
    blockInput.setRange(0, saltBytes.length, saltBytes);
    blockInput[saltBytes.length + 3] = 1;

    var u = Uint8List.fromList(hmac.convert(blockInput).bytes);
    final result = Uint8List.fromList(u);

    // 2047 additional iterations
    for (int i = 1; i < 2048; i++) {
      u = Uint8List.fromList(hmac.convert(u).bytes);
      for (int k = 0; k < 64; k++) {
        result[k] ^= u[k];
      }
    }

    return result;
  }

  /// Deterministically derives master Ed25519 signing keypair from 12-word mnemonic
  static Future<SimpleKeyPair> deriveSigningKeyPair(String phrase) async {
    final seed = mnemonicToSeed(phrase);
    final seed32 = seed.sublist(0, 32);
    final ed25519 = Ed25519();
    return await ed25519.newKeyPairFromSeed(seed32);
  }

  /// Suggests matching BIP-39 words for auto-complete typing
  static List<String> suggestWords(String prefix) {
    if (prefix.trim().isEmpty) return const [];
    final clean = prefix.trim().toLowerCase();
    return bip39EnglishWords.where((w) => w.startsWith(clean)).take(5).toList();
  }
}
