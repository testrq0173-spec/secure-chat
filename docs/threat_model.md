# Bharosa: Threat Model & Security Architecture

## 1. Overview & Privacy Goals
Bharosa is designed as a zero-knowledge, zero-identifier, asynchronous messenger inspired by the SimpleX Chat architecture, with Firebase as a blinded, encrypted transport postbox.

### Core Security Guarantees:
1. **Zero User Identifiers:** No phone number, no email, no central username, no persistent user directory.
2. **Pairwise Unidirectional Queues:** Each conversation between Alice and Bob uses two distinct 128-bit capability-addressed queues (Queue A→B and Queue B→A). There is no single "chat room" on the server.
3. **Double Ratchet Forward Secrecy & Break-in Recovery:** Every message is encrypted under a unique ephemeral key derived using Diffie-Hellman ratcheting. Compromise of a message key reveals neither past nor future messages.
4. **Queue Blindness:** The Firebase relay server only sees opaque encrypted blobs. It cannot inspect sender, receiver, message content, media keys, or conversation graphs.
5. **Constant-Size Padding Buckets:** All message payloads are padded to discrete power-of-two/bucket lengths (128B, 512B, 2KB, 8KB, 32KB) before encryption to mitigate traffic analysis.
6. **Encrypted Local Storage:** All chat history, contacts, ratchet states, and cryptographic keys are encrypted at rest using a high-entropy key stored in the device hardware Keystore/Keychain, locked behind a user PIN/Biometrics.

---

## 2. Threat Actors & Mitigations

| Threat Actor | Capabilities | Bharosa Protection / Mitigation | Residual Risk |
|---|---|---|---|
| **Passive Network Eavesdropper** (ISP, Wi-Fi snooper, coffee shop hacker) | Inspects TLS traffic, IP addresses, packet sizes | End-to-end TLS + ChaCha20-Poly1305 double encryption + constant size padding buckets. | Can observe connection to Firebase endpoint. |
| **Malicious or Compromised Firebase Server** (Google infrastructure compromise, rogue admin) | Reads Firestore documents, Storage blobs, timing, and queue document metadata | Firebase stores only encrypted envelopes. No phone numbers, no contacts, no message plaintexts. Packets are deleted immediately upon client delivery. Cloud Functions verify cryptographic Ed25519 signatures before granting queue write access. | Google infrastructure observes IP addresses and queue communication timestamps (can correlate timing between send and receive queues). |
| **Malicious Peer / Untrusted Contact** | Tries to forge messages, replay packets, or enumerate queues | Queue IDs are 128-bit cryptographic random tokens (unguessable capability URLs). Messages carry authenticated ratchet headers and replay counters. Reject out-of-window duplicates. | If user connects to an attacker, attacker knows what they sent. Reusable contact addresses can be deleted/revoked at any time. |
| **Device Theft / Physical Seizure** | Attacker obtains unlocked or locked physical device | Local SQLite DB is encrypted. Hardware Keystore / Keyring guards master key. App auto-locks with timeout. Screen protector prevents recent apps preview and screenshot capture. Optional duress code wipes sensitive contacts. | If device is seized while unlocked with user coerced into entering PIN. |
| **Man-in-the-Middle (MitM) during Connection** | Attacker tampers with invite link or QR code in transit | In-person or out-of-band **Safety Number / Security Code verification** (6-digit numeric match + QR verification). The security code is computed as SHA256(AlicePubKey || BobPubKey). | If users do not verify safety numbers and an attacker altered the initial invite link over an insecure medium. |

---

## 3. Cryptographic Primitives & Specifications
- **Key Exchange (KEM / ECDH):** X25519 (Curve25519 Diffie-Hellman)
- **Digital Signatures:** Ed25519 for capability queue authentication and handshake proof
- **Symmetric Cipher:** ChaCha20-Poly1305 AEAD (RFC 8439) with 256-bit keys and 96-bit unique nonces
- **Key Derivation (KDF):** HKDF-SHA256 (RFC 5869) for symmetric ratcheting and key separation
- **Queue IDs:** 128-bit cryptographically secure pseudorandom token (CSPRNG) encoded in URL-safe Base64
- **Safety Number:** 6-digit grouped numeric display and verification QR derived from mutual identity public keys
- **Padding:** Bucket thresholds at 128, 512, 2048, 8192, 32768 bytes with PKCS#7 / length-prefixed random fill.
