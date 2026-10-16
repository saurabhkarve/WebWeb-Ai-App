# Building WebWeb Ai with Codemagic

`codemagic.yaml` has two workflows:

- **android-release** builds an `.aab` for Play and an `.apk` for direct installs.
- **ios-release** builds an `.ipa` and uploads it to TestFlight.

Both run when you push a tag starting with `v`, for example `v0.2.0`. You can also start either one with **Start new build** in Codemagic.

App ids:

- Android: `in.allpos.allpos_app`. This is unchanged because it is already registered in Firebase.
- iOS: `ai.webweb.app`.

Production API: `https://biznetapi.webweb.ai`, set as `API_URL` in the yaml.

## 0. Accounts you need
- **Codemagic.** Sign in at https://codemagic.io with the GitHub account that can see `saurabhkarve/WebWeb-Ai-App`.
- **Firebase.** Use the project `webweb-ai` in the Firebase console.
- **Apple Developer Program.** It costs $99 a year and is needed for iOS builds and TestFlight.
- **Google Play Console.** It is a one-time $25 fee and is needed for the Play Store.

## 1. Firebase (push notifications)
1. In Firebase, open Project settings, then Your apps.
   - **Android.** The app `in.allpos.allpos_app` should already exist. Download `google-services.json`.
   - **iOS.** Click **Add app**, choose iOS, and set the bundle id to `ai.webweb.app`. Download `GoogleService-Info.plist`. Do not add it to Xcode; the build passes its values in instead.
2. Add the APNs key so Firebase can reach iPhones:
   1. In Apple Developer, go to Certificates, IDs & Profiles, then **Keys**, then **+**. Enable *Apple Push Notifications service (APNs)* and download the `.p8` file.
   2. In Firebase, go to Project settings, then **Cloud Messaging**, then *Apple app configuration*.
   3. Upload the `.p8` with its Key ID and your Team ID.
3. Server side:
   1. In Firebase, go to Project settings, then **Service accounts**, then **Generate new private key**.
   2. Send that JSON to the person who runs the server. It becomes `FIREBASE_SERVICE_ACCOUNT` in `api/.env`.
   3. Until it is set, the API sends no pushes. The app still works, without notifications.

## 2. Codemagic: add the app
1. In Codemagic, go to **Apps**, then **Add application**, then GitHub, and pick `WebWeb-Ai-App`.
2. When asked, choose **codemagic.yaml** as the configuration. It is read from the repo root.

## 3. Codemagic: environment variables
Open the app, then **Environment variables**. Add these and tick **Secure** for each.

| Group | Variable | Value |
|---|---|---|
| `firebase` | `GOOGLE_SERVICES_JSON` | Output of `base64 -i google-services.json \| pbcopy`. Paste it in. |
| `firebase` | `FIREBASE_IOS_API_KEY` | `API_KEY` from `GoogleService-Info.plist` |
| `firebase` | `FIREBASE_IOS_APP_ID` | `GOOGLE_APP_ID` from the plist, like `1:1234:ios:abcd` |
| `firebase` | `FIREBASE_SENDER_ID` | `GCM_SENDER_ID` from the plist |
| `app_store` | `APP_STORE_APPLE_ID` | The numeric Apple ID of the app (step 5) |

## 4. Android signing (keystore)
If the team already has the upload keystore (`upload-keystore.jks`), use that one. Play only accepts updates signed with the same key. Otherwise create one once:

```bash
keytool -genkey -v -keystore upload-keystore.jks -keyalg RSA -keysize 2048 -validity 10000 -alias upload
```

Then add it to Codemagic:

1. Go to **Team settings**, then **Code signing identities**, then **Android keystores**, then **Add keystore**.
2. Upload the `.jks`.
3. Enter the passwords and alias `upload`.
4. Set **Reference name** to `webweb_upload`.

Keep a backup of the `.jks` file and its passwords. If you lose them, you cannot update the app on Play.

## 5. iOS signing (App Store Connect API key)
1. In App Store Connect, go to **Users and Access**, then **Integrations**, then **App Store Connect API**, then **+**.
   - Use the role **App Manager**.
   - Download the `.p8` file. Note the **Issuer ID** and **Key ID**.
2. In Codemagic, go to **Team settings**, then **Integrations**, then **Developer Portal**, then **Manage keys**, then **Add key**.
   - Name it exactly `WebWeb ASC`.
   - Enter the Issuer ID and Key ID, and upload the `.p8`.
3. In Apple Developer, go to **Identifiers**, then **+**, then App IDs.
   - Bundle ID: `ai.webweb.app`.
   - Under Capabilities, tick **Push Notifications**.
   - If Codemagic already created this App ID, just edit it and tick Push Notifications.
4. In App Store Connect, go to **Apps**, then **+**, then **New App**.
   - Platform: iOS. Name: *WebWeb Ai*. Bundle ID: `ai.webweb.app`. SKU: `webweb-ai`.
   - Open the new app, then **App Information**. Copy the **Apple ID** (a number) into `APP_STORE_APPLE_ID`.
5. Codemagic then creates the distribution certificate and provisioning profile on its own, because the yaml has `ios_signing`. You do not need a Mac for this.

## 6. Build
- **From Codemagic:** open the app, click **Start new build**, then pick a workflow (`android-release` or `ios-release`) and the `main` branch.
- **Or by tag:** run

  ```bash
  git tag v0.2.0 && git push origin v0.2.0
  ```

  This starts both workflows.

Each build:

- uses the next Codemagic build number on Android;
- uses the latest TestFlight build number plus 1 on iOS;
- takes the version name from `version:` in `pubspec.yaml`. Bump it for each store release.

Results:

- **Android:** the `.aab` and `.apk` appear under the build's Artifacts, and you also get an email. For the first release, upload the `.aab` by hand in Play Console under Testing, then Internal testing. After that you can switch on the `google_play` block in the yaml for automatic uploads.
- **iOS:** the `.ipa` goes straight to TestFlight. After Apple finishes processing, which takes about 10 to 30 minutes, add testers in App Store Connect under TestFlight.

## Notes
- **iOS incoming calls.** When the app is closed, a call shows as a notification. Tapping it opens the app and the call connects. A full-screen ringing screen on iOS would need CallKit and PushKit (VoIP), which is a later step.
- **Permissions.** The app asks for each one only when it is first used:
  - contacts: Refer, or sharing a contact in chat;
  - location: Use my location, Detect, or a location in chat;
  - camera, photos, microphone;
  - notifications: right after signing in.

  The wording iOS shows is in `ios/Runner/Info.plist`.
