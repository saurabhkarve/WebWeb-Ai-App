# Play Store checklist - WebWeb Ai

## Architecture (what the app talks to)
- API: `https://biznetapi.webweb.ai` (the same API as the web, repo `api/`). The app needs the **additive app layer** from the root README deployed there:
  migration `008_app_realtime.sql`, the `/app/*` routes, the WebSocket `/app/ws` (nginx must pass `Upgrade`/`Connection` headers), and `FIREBASE_SERVICE_ACCOUNT` for push.
- Login: the API's own phone OTP (`/auth/send-otp`, `/auth/verify-otp`). For the public release the API must send **real SMS** (`OTP_MODE=msg91`, DLT template, see `api/src/sms.ts`)
  - or use the optional Firebase route `POST /app/auth/firebase`.
- Release builds are https-only (cleartext is allowed only in debug builds).

## Done in the project
- Release signing with an upload keystore (`android/app/upload-keystore.jks`, passwords in `android/key.properties`; both gitignored). **Back both up** - if lost you cannot update the app without a Google reset.
- Store graphics: `icon-512.png`, `feature-graphic.png`. Text drafts: `STORE_LISTING.md`, `PRIVACY_POLICY.md`, `DATA_SAFETY.md`.

## You need to do
1. Google Play Console developer account ($25). Personal accounts created after Nov 2023 need a **closed test with 12+ testers for 14 days** before production.
2. Host `PRIVACY_POLICY.md` on a public page (e.g. https://webweb.ai/privacy) and fill the contact details.
3. Deploy the API changes above on the live server and set up real SMS.
4. **Package name** is still `in.allpos.allpos_app`. Decide the final id (e.g. `ai.webweb.app`) *before* the first upload - it can never change after publishing. Then in Firebase (project `webweb-ai`) add an Android app with that id, download the new `google-services.json` into `android/app/`, and change `applicationId`/`namespace` + `MainActivity` package.
5. Firebase: add the SHA-1 / SHA-256 of the upload key and, after the first upload, of the Play App Signing key (Play Console > Setup > App signing).
6. Build: `flutter build appbundle --release --dart-define=API_URL=https://biznetapi.webweb.ai`, upload `build/app/outputs/bundle/release/app-release.aab` (internal testing first).

Upload key fingerprints (for Firebase):
- SHA-1:   `1E:C2:40:A7:6D:44:FB:1A:CC:B2:A0:94:C8:35:FE:37:7E:17:72:F1`
- SHA-256: `00:DE:98:E7:8B:21:23:FD:56:53:21:2E:4B:EB:55:30:51:DD:C7:C2:28:C4:0A:8D:4A:C3:C8:81:13:2B:B5:51`

## Play Console forms
- Privacy policy URL; Data safety (`DATA_SAFETY.md`); Content rating (user generated content); Target audience 18+; no ads.
- Permissions: `READ_CONTACTS` (user picks contacts to refer on an ask), `RECORD_AUDIO` / `CAMERA` (voice and video calls), `POST_NOTIFICATIONS`, `USE_FULL_SCREEN_INTENT` (incoming call screen).
- Account deletion: Play requires an in-app way **and** a web URL. Not built yet.

## Still to build before a public release
- [ ] In-app "delete my account" + web page (needs an API route).
- [ ] Report / block user for chats and asks (UGC policy).
- [ ] Background call ringing works through FCM data pushes; test on Android 13/14 with the app killed.
