# Private Secure Chat App: Poora Blueprint

SimpleX Chat se inspired ek apna private messenger. Flutter (mobile) + Firebase (backend), modern premium light-only UI.

> **Status:** Planning document v2 (decisions finalize ho chuke hain, section 13 dekho)
> **Platform:** Android pehle, Flutter code iOS-ready rahega
> **Reference:** https://simplex.chat/ aur https://github.com/simplex-chat/simplex-chat

---

## 1. Overview

### Goal
Ek aisa chat app jisme:
- Signup ke liye phone number, email ya username **nahi** chahiye
- Message content sirf sender aur receiver padh sakte hain (end-to-end encrypted)
- Saari chat history sirf user ke phone pe, encrypted rehti hai
- Connection sirf invite link ya QR code se banta hai (isliye spam nahi)
- UI modern, premium aur **sirf light theme** mein

### Kya hum SimpleX ki copy nahi bana rahe
SimpleX ka network design (disposable relay servers, private message routing, no identifiers) bahut advanced hai. Hum uski **privacy philosophy aur features** follow karenge, lekin backend Firebase hoga. Iska matlab kuch limitations hain, jo agle section mein clear likhe hain.

---

## 2. Firebase ke saath honest limitations

| Cheez | SimpleX | Hamara app (Firebase) |
|---|---|---|
| Message content | Encrypted | **Encrypted** (same level ka target) |
| User identifier | Koi nahi | Anonymous Firebase UID (random, per install) |
| Server ko pata: kaun kisse baat kar raha | Nahi | Partially: queue IDs aur timing dikhti hai |
| IP address | Private routing se chhupta hai | Firebase/Google ko dikhta hai |
| Server kaun chalata hai | Koi bhi chala sakta hai | Sirf hum (Google infra pe) |
| Tor / proxy support | Hai | V1 mein nahi |

**Matlab:** content 100% safe, lekin metadata (kaun, kab, kitna) Google ke liye theoretically visible rahega. Yeh app "very private" hoga, "SimpleX-level anonymous" nahi. Future mein apna relay server lagake yeh gap band kiya ja sakta hai (Phase 5).

**Design rule:** Firebase ko sirf ek **andha postbox** ki tarah use karenge. Usme sirf encrypted packets honge, aur wo bhi receive hone tak.

---

## 3. Tech Stack

| Layer | Choice | Kaam |
|---|---|---|
| Mobile app | Flutter (Android + iOS) | Ek codebase |
| State management | Riverpod | App state |
| Navigation | go_router | Screens aur deep links |
| Local database | Drift + SQLCipher | Encrypted chat history |
| Secure key storage | flutter_secure_storage (Keystore / Keychain) | Private keys aur DB passphrase |
| Cryptography | libsodium (ya audited Signal-protocol binding) | Key exchange, encryption |
| Backend | Firebase Auth (anonymous), Firestore, Storage, FCM | Encrypted relay |
| Server logic | Cloud Functions (minimal) | Queue access verification, cleanup |
| QR | qr_flutter + mobile_scanner | Invite QR dikhana aur scan karna |
| Calls | flutter_webrtc | Audio/video calls |
| App lock | local_auth + custom passcode | Biometric aur PIN |
| Screenshot block | screen_protector (ya equivalent) | Recent apps aur screenshots block |
| Fonts | Inter (google_fonts) | Typography |

> Package names aur versions build ke waqt ek baar verify kar lena, kyunki ecosystem badalta rehta hai.

---

## 4. Security Architecture

### 4.1 Identity (koi account nahi)
- App pehli baar khulne pe Firebase **anonymous sign-in** hota hai. Koi email ya phone nahi.
- User sirf ek **display name** aur optional photo choose karta hai. Yeh sirf phone pe rehta hai aur sirf connection ke time contact ko bheja jata hai (encrypted).
- Har contact ke liye **alag identity keys** banti hain. Do contacts ke beech koi common identifier nahi hota.
- **Incognito mode:** har contact ko ek naya random naam dikhta hai.

### 4.2 Pairwise queues (SimpleX ka core idea)
- Har conversation ke liye 2 one-way queues: ek A se B ko, ek B se A ko.
- Har queue ka ek **random lamba ID** (kam se kam 128-bit random) hota hai.
- Queue ID ek capability ki tarah kaam karta hai: jisko pata hai wahi use kar sakta hai.
- Queue ke saath ek public key register hoti hai. Cloud Function har read, write aur delete pe **signature verify** karti hai, taaki sirf sahi device hi queue use kar sake.

### 4.3 Encryption layers
1. **Message encryption:** double-ratchet style, har message ki apni key. Forward secrecy aur break-in recovery.
2. **Queue-level encryption:** ek extra layer, taaki same ciphertext do jagah na dikhe.
3. **Padding:** message sizes ko fixed buckets mein pad karna.
4. **Transport:** sirf TLS.
5. **Local database:** SQLCipher, passphrase user ke app lock se tied.
6. **Local files:** images aur files bhi phone pe encrypted store hongi.

> **Zaroori:** apna crypto khud scratch se mat likhna. Proven library use kar, aur launch se pehle kisi security expert se **review** karwana.

### 4.4 Message lifecycle
1. Sender message encrypt karta hai.
2. Encrypted packet receiver ki queue mein jata hai (Firestore).
3. Receiver ko push notification milti hai (sirf "naya message", koi content nahi).
4. Receiver packet download karke decrypt karta hai aur apne local DB mein save karta hai.
5. Receiver ka app Firestore se packet **delete** kar deta hai.
6. Safety net: Cloud Function purane undelivered packets ko 30 din baad auto-delete karti hai.

### 4.5 Push notifications
- FCM token sirf receiver ke queue-doc se juda hota hai.
- Notification mein content kabhi nahi: sirf generic alert, jaise "Naya message".
- User setting: notification preview band, ya notification bilkul band.

### 4.6 Firestore security rules ke principles
- Default: sab kuch deny.
- Queue create karne ke liye authenticated (anonymous) user chahiye.
- Read, delete sirf valid signature wale device ko.
- Koi list ya query allowed nahi: sirf exact queue ID se access, taaki koi queues browse na kar sake.
- Message size aur rate limit enforce karna.

### 4.7 Cloud backup (Firebase, per user)
- User backup on karta hai to app ek **12-word recovery phrase** banata hai aur user ko likh ke rakhne ko bolta hai.
- Backup ka saara data (chats, contacts, keys, profiles) **phone pe hi encrypt** hota hai, recovery phrase se nikli key se. Firebase ko sirf encrypted blob dikhta hai.
- Har user ka apna alag backup hota hai (per user). Backup ek **random backup ID** ke neeche rakha jata hai, jo recovery phrase se derive hota hai, Firebase UID se nahi. Isliye naye phone pe (naya anonymous UID) bhi restore ho jata hai, aur backup ID guess karna practically impossible hai.
- Auto backup: daily ya weekly, sirf Wi-Fi pe (user choice). Sirf latest 1 se 2 versions rakhe jaate hain.
- **Backup default OFF** rahega, user khud on karega.
- Recovery phrase kho gaya to backup wapas nahi aayega, aur hum bhi recover nahi kar sakte. Yeh warning clearly dikhani hai.
- Restore ke baad purani ratchet state stale ho sakti hai, isliye har contact ke saath keys re-sync ya queue rotate hoga.
- Trade-off: chat history ki ek encrypted copy cloud mein hogi. Phrase weak ya leak hui to risk hai, isliye strong phrase aur clear user guidance zaroori hai.

---

## 5. Connection Flow (invite link / QR)

### One-time invite (default)
1. **Alice** "New connection" dabati hai. App ek invitation banata hai: Alice ki public keys + ek naya queue address.
2. App ek **link** aur **QR** dikhata hai.
3. Alice link bheji (kisi bhi channel se, jaise WhatsApp, SMS) ya QR in-person dikhati hai.
4. **Bob** link kholta hai ya QR scan karta hai. App Alice ki keys padhta hai.
5. Bob apni keys ke saath ek **connection request** Alice ki queue mein bhejta hai (encrypted).
6. Alice ko notification aati hai, wo accept karti hai, aur dono taraf ki queues ban jaati hain.
7. Dono ke app mein **"Connected"** dikhta hai. Link ab expire ho jata hai.

### Optional: reusable contact address
- Public use ke liye ek long-term address (jaise social media bio mein). Alice har request ko manually accept ya reject karti hai. Jab chahe delete kar sakti hai.

### Security code verification
- Connection ke baad dono taraf ek **security code** (number ya QR) dikhta hai.
- Dono in-person ya call pe match karte hain. Match hone pe contact pe **"Verified"** badge lagta hai.

> Link channel secure hona zaroori nahi, bas yeh pata hona chahiye ki link kisne bheji.

---

## 6. Data Model

### 6.1 Firestore (backend, minimal)
| Collection | Kya rakhta hai | Retention |
|---|---|---|
| `queues/{queueId}` | Queue ki public key, push token reference, created time | Jab tak queue delete na ho |
| `queues/{queueId}/packets/{packetId}` | Encrypted packet, size, time | Receive hone tak, max 30 din |
| `invites/{inviteId}` | One-time invite ka encrypted data | Use hone pe ya 7 din baad delete |

Firebase mein **koi** user profile, contact list, group list ya readable message nahi hoga.

### 6.2 Firebase Storage
- Sirf **encrypted file chunks**. File key message ke andar jaati hai, Storage mein kabhi nahi.
- Encrypted user backups (section 4.7), random backup ID ke neeche.
- Download ke baad ya expiry pe delete.

### 6.3 Local database (sirf phone pe, SQLCipher)
| Table | Fields (concept) |
|---|---|
| profiles | id, display name, photo, hidden flag, created |
| contacts | id, profile, name, avatar, verified, queue refs, keys ref, created |
| conversations | id, type (direct, group), last message, unread, muted, disappearing timer |
| messages | id, conversation, sender, type, body, status, time, expires at, reply to, edited |
| reactions | message, contact, emoji |
| groups | id, name, avatar, role of me |
| group_members | group, contact, role |
| files | id, message, path, size, type, encrypted flag |
| settings | key, value |

---

## 7. Flutter Project Structure

```
lib/
├─ main.dart
├─ app/
│   ├─ app.dart                  (root widget, light theme only)
│   ├─ router.dart               (go_router routes, deep links)
│   └─ bootstrap.dart            (Firebase init, key store, DB open)
├─ core/
│   ├─ theme/                    (colors, typography, spacing, radius, shadows)
│   ├─ widgets/                  (shared premium components)
│   ├─ crypto/                   (key generation, ratchet, padding, queue crypto)
│   ├─ storage/                  (secure storage, encrypted DB setup)
│   ├─ network/                  (Firebase gateway, retry, rate handling)
│   ├─ notifications/            (FCM handling, local notifications)
│   └─ utils/
├─ data/
│   ├─ local/                    (Drift tables, DAOs)
│   ├─ remote/                   (queue API, file API)
│   └─ repositories/
├─ features/
│   ├─ onboarding/
│   ├─ profile/                  (profiles, incognito, hidden profiles)
│   ├─ connect/                  (create invite, scan, accept, verify)
│   ├─ chats/                    (chat list, chat screen, composer)
│   ├─ groups/
│   ├─ media/                    (images, files, voice, video)
│   ├─ calls/                    (WebRTC audio, video)
│   ├─ security/                 (app lock, passcode, screenshot block)
│   └─ settings/
└─ l10n/                         (English, Hindi, aur future languages)

functions/                       (Cloud Functions: verify, cleanup)
firebase/                        (security rules, indexes)
docs/                            (architecture, threat model, this blueprint)
```

---

## 8. UI aur Design System (Light theme only)

### 8.1 Design principles
- **Calm aur spacious:** zyada white space, kam clutter.
- **Premium feel:** soft shadows, rounded corners, smooth animations.
- **Privacy ko dikhana:** lock icons, "Verified" badge, encryption status subtle tareeke se.
- **Ek hi accent colour** (Ultraviolet), baaki sab neutral.
- **Sirf light theme.** Dark mode ka koi toggle nahi.

### 8.2 Colour palette (FINAL)

| Naam | Hex | Kahan use hoga |
|---|---|---|
| Ink | `#14121F` | Main text, icons, chhote dark highlights |
| Ultraviolet | `#6C4CFF` | Primary buttons, send button, sent bubbles, links, active tab |
| Lavender | `#D9D1FF` | Received bubbles, tags, selected states, input focus |
| Paper | `#F7F6F2` | App background |
| White | `#FFFFFF` | Cards, input fields, bottom sheets |
| Grey 500 | `#6B6880` | Secondary text, timestamps |
| Grey 200 | `#E6E3EE` | Borders, dividers |
| Success | `#1F9D6B` | Delivered, verified |
| Warning | `#E5A100` | Cautions |
| Error | `#D93F4C` | Failures, security code mismatch |

> Lavender aur Paper kaafi paas hain, isliye cards ko alag dikhane ke liye White surface aur halka border use karna.

### 8.3 Typography (Inter)
| Style | Size | Weight | Use |
|---|---|---|---|
| Display | 28 | Bold | Onboarding titles |
| Title | 20 | Semibold | Screen titles |
| Body | 16 | Regular | Messages, lists |
| Caption | 13 | Regular | Timestamps, hints |
| Button | 16 | Semibold | Buttons |

### 8.4 Spacing, shape, motion
- Spacing scale: 4, 8, 12, 16, 24, 32.
- Corner radius: buttons 14, cards 20, message bubbles 18 (tail wali side 6), bottom sheets 28.
- Shadows: bahut halke, blur zyada, opacity kam.
- Motion: 200 se 300 ms ease-out. Bubble aane ki halki animation, screen transitions smooth.
- Haptics: send aur connect pe halka feedback.

### 8.5 Reusable components
Primary / secondary / text buttons, chat bubble (sent, received, with reply, with reaction), avatar (initials fallback), chat list tile, input composer, security badge, empty state illustration, bottom sheet, toast, segmented tabs, QR card, passcode keypad.

---

## 9. Screens

| # | Screen | Kya dikhta hai aur kya hota hai |
|---|---|---|
| 1 | **Splash** | Logo, key setup background mein |
| 2 | **Onboarding (3 slides)** | "No phone number", "Tu apne data ka owner", "Link se connect". Skip option |
| 3 | **Create profile** | Display name, optional photo. Koi email ya phone nahi |
| 4 | **Set app lock** | PIN banana, biometric enable (optional) |
| 5 | **Chat list (Home)** | Search, chats ki list, unread count, muted icon, FAB "New connection" |
| 6 | **New connection** | 2 tabs: "Create invite" (link + QR) aur "Scan / Paste link" |
| 7 | **Scan QR** | Camera, scanning frame, torch toggle |
| 8 | **Connection request** | Accept ya reject, naam, security info |
| 9 | **Chat screen** | Header (naam, verified badge, call icons), messages, composer |
| 10 | **Message actions** | Reply, react, copy, edit, delete (sirf mere liye ya sabke liye), forward |
| 11 | **Contact info** | Photo, naam, security code verify, disappearing timer, mute, block, delete |
| 12 | **Security code** | Number aur QR, "Mark as verified" |
| 13 | **Create group** | Naam, avatar, contacts select |
| 14 | **Group info** | Members, roles, invite link, leave |
| 15 | **Media viewer** | Image, video full screen, zoom, save (optional) |
| 16 | **Voice recorder** | Hold to record, slide to cancel |
| 17 | **Call screen** | Audio aur video, mute, speaker, camera flip, end |
| 18 | **Profiles** | Multiple profiles, hidden profile (password se unlock), incognito toggle |
| 19 | **Settings** | Privacy, security, notifications, storage, appearance (accent only), about |
| 20 | **Privacy and Security settings** | App lock timeout, screenshot block, notification preview, delivery receipts |
| 21 | **Backup and Restore** | Cloud backup on ya off, recovery phrase dikhana aur confirm karna, restore flow |
| 22 | **Lock screen** | PIN ya biometric prompt |

---

## 10. Functionality: Phase-wise Roadmap

### Phase 0: Foundation (1 se 2 hafte)
**Kaam**
- Flutter project setup, folder structure, flavors (dev, prod)
- Firebase project setup (dev aur prod alag)
- Design system: colors, typography, components
- Secure key storage, encrypted local DB setup
- Threat model document likhna (kisse kya protect karna hai)

**Done jab:** app khulta hai, theme sahi dikhta hai, encrypted DB open hota hai, anonymous login chalta hai.

---

### Phase 1: Core private chat (4 se 6 hafte)
**Kaam**
- Onboarding, profile creation, app lock (PIN, biometric)
- Invite link aur QR se connection (one-time invite)
- Pairwise queues, signature verification (Cloud Functions)
- 1-to-1 end-to-end encrypted messaging
- Local encrypted chat history
- Message status: sending, sent, delivered, failed
- Push notifications (content ke bina)
- Security code verification
- Delete for me / delete for everyone
- Disappearing messages (per contact timer)
- Incognito mode
- **Reusable contact address** (optional, manual accept ya reject, jab chahe delete)

**Done jab:** do real phones ke beech link se connect hokar encrypted chat chalti hai, Firebase console mein sirf ciphertext dikhta hai.

---

### Phase 2: Rich messaging aur groups (4 se 6 hafte)
**Kaam**
- Images, files (encrypted, Firebase Storage)
- Voice messages
- Video messages
- Message reply, reactions, edit (with edit history)
- Draft messages save hona
- Private notes (khud ko notes)
- Groups: create, add members, roles (owner, admin, member), group invite link
- Chat search (local)
- Mute, archive chats

**Done jab:** media aur groups stable hain, aur group mein encrypted messages sabko pahunchte hain.

---

### Phase 3: Calls aur advanced privacy (3 se 5 hafte)
**Kaam**
- End-to-end encrypted audio calls (WebRTC)
- Video calls
- Multiple profiles, hidden profiles
- Screenshot block aur recent apps blur
- Alternative (duress) passcode: optional
- Notification preview control
- Encrypted cloud backup aur restore (Firebase, recovery phrase se, section 4.7)
- Manual queue rotation (conversation ko naye queue pe move karna)

**Done jab:** calls dono network pe stable chalte hain, backup restore se chats wapas aati hain.

---

### Phase 4: Polish aur launch (3 se 4 hafte)
**Kaam**
- Animations aur micro-interactions
- Hindi aur ek-do aur languages
- Accessibility (font scaling, screen reader labels, contrast)
- Performance (chat scroll, battery, app size)
- Crash reporting (privacy-friendly, bina personal data ke)
- **External security review** (zaroori)
- Google Play Store submission, data safety form, store listing

**Done jab:** security review ke issues fix, beta testers ka feedback incorporate, stores pe approval.

---

### Phase 5: Future (optional)
- Apna relay server (Firebase ki jagah), taaki metadata privacy bhi mile
- Automatic queue rotation aur multi-server redundancy
- Message mixing (timing correlation se bachne ke liye)
- Tor ya proxy support
- Post-quantum key exchange
- Large groups aur public channels
- iOS release (App Store, push notification testing ke saath)
- Desktop app (Flutter desktop)
- Bots aur automation API

---

## 11. Feature Checklist (SimpleX ke comparison mein)

| Feature | Phase | Note |
|---|---|---|
| No phone, no email signup | 1 | Anonymous auth |
| Invite link aur QR | 1 | Core |
| Reusable contact address | 1 | Optional, manual accept |
| E2E encrypted 1-to-1 chat | 1 | Core |
| Local encrypted DB | 1 | Core |
| App passcode, biometric | 1 | |
| Disappearing messages | 1 | |
| Incognito mode | 1 | |
| Security code verification | 1 | |
| Delete for everyone | 1 | |
| Images, files | 2 | |
| Voice, video messages | 2 | |
| Reply, reactions, edit | 2 | |
| Groups | 2 | |
| Private notes | 2 | |
| Audio, video calls | 3 | |
| Multiple, hidden profiles | 3 | |
| Screenshot block | 3 | |
| Encrypted cloud backup | 3 | Firebase Storage, per user, recovery phrase |
| Queue rotation (manual) | 3 | |
| Private message routing | 5 | Apna server chahiye |
| Tor support | 5 | |
| Public channels | 5 | |

---

## 12. Testing Plan

- **Unit tests:** crypto helpers, message encode, decode, padding.
- **Integration tests:** connection flow, send, receive, delete lifecycle.
- **Two-device testing:** har phase ke end pe real Android + iOS devices pe.
- **Security tests:**
  - Firestore rules ko emulator pe test karna (dusre ki queue read karne ki koshish)
  - Replay aur tampered packet reject hona
  - Backend data inspect karke confirm karna ki kuch readable nahi
  - App background mein jaye to screen blur ho raha hai ya nahi
- **Network tests:** weak internet, offline, app kill, reinstall.
- **Device matrix:** purane aur naye Android, kuch iPhones, alag screen sizes.

---

## 13. Risks aur Decisions

| Risk | Impact | Plan |
|---|---|---|
| Crypto implementation mein galti | Bahut bada | Proven library, external review, Phase 4 mein audit |
| Firebase metadata visibility | Medium | Users ko clearly batana, Phase 5 mein apna relay |
| Background notifications (Android battery optimization, baad mein iOS limits) | Medium | Early testing alag-alag Android brands pe, generic push design |
| Backup ya restore mein keys lose hona | Medium | Clear warning, encrypted backup with passphrase |
| App store policies (encryption export) | Chhota | Encryption declaration, privacy labels sahi bharna |
| Firebase cost badhna (heavy file use) | Medium | File size limits, auto-delete, monitoring |

### Final decisions

| # | Decision | Final jawab |
|---|---|---|
| 1 | Platform | **Android pehle.** Flutter code iOS-ready rahega, iOS release Phase 5 mein |
| 2 | App ka naam aur logo | **Recommended: Bharosa** (Hindi mein "trust"). Alternates: Amanat, Kavach. Logo: Ultraviolet rang mein shield aur chat bubble ka simple combo. Play Store aur trademark availability check karna baaki hai |
| 3 | Palette | **Final.** Ink, Ultraviolet, Lavender, Paper, plus section 8.2 ke supporting colours |
| 4 | Reusable contact address | **Phase 1 mein** |
| 5 | Backup | **Cloud mein (Firebase), encrypted, per user**, recovery phrase se, default OFF (section 4.7) |

---

## 14. Agle Steps

1. App name final karna (Play Store aur trademark check ke baad) aur logo banana
2. Phase 0 shuru: Flutter project (Android focus), Firebase setup, design system
3. Threat model aur crypto approach ka short document
4. Phase 1 ke screens ke wireframes ya mockups banana
5. Pehla working prototype: do Android phones ke beech ek encrypted message

---

*Yeh ek living document hai. Har phase ke baad update karna.*