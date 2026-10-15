# WebWeb Ai - Flutter app

Android app for WebWeb AI. It uses the **same API as the web** (`../api`), so accounts, asks, chats and catalog are shared.

## Run
```bash
flutter pub get
adb reverse tcp:4000 tcp:4000      # API on your PC reachable as localhost:4000 from the phone
flutter run                         # default API_URL = http://localhost:4000
```
Local API: see the root README (`OTP_MODE=dev`, OTP `123456`).

## Build for Play Store
```bash
flutter build appbundle --release --dart-define=API_URL=https://biznetapi.webweb.ai
```
Signing: `android/key.properties` + `android/app/upload-keystore.jks` (both gitignored - back them up).
See `store/PLAY_STORE_CHECKLIST.md`.

## Structure
- `lib/api.dart` HTTP client (same contract as `web/src/lib/api.ts`), `lib/models.dart` types + option lists (mirror `web/src/lib/types.ts` / `constants.ts`)
- `lib/auth_provider.dart` login (`/auth/send-otp`, `/auth/verify-otp`) + profile (`/me`)
- `lib/realtime.dart` WebSocket (`/app/ws`), `lib/call_manager.dart` WebRTC calls, `lib/notifications.dart` FCM + local notifications
- `lib/screens/` Connect, Find, Talk, Ask, Profile, onboarding; `lib/widgets/` post card, story viewer, loaders
