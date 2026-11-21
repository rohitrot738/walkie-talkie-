# Walkie Talkie

Frequency-based push-to-talk app. Same frequency = same room. Range: 1.0 – 999.9 MHz (0.1 step).

- `server.js` – Node + Socket.IO signaling server (WebRTC audio is peer-to-peer)
- `public/` – web client
- `mobile/` – Flutter mobile app

## Run
```
npm install && node server.js
cd mobile && flutter create . && flutter pub get && flutter run
```
### Background mode (Android)
After `flutter create .`, in `android/app/src/main/AndroidManifest.xml` add inside `<manifest>`:
```xml
<uses-permission android:name="android.permission.FOREGROUND_SERVICE"/>
<uses-permission android:name="android.permission.FOREGROUND_SERVICE_MICROPHONE"/>
<uses-permission android:name="android.permission.POST_NOTIFICATIONS"/>
<uses-permission android:name="android.permission.WAKE_LOCK"/>
```
and inside `<application>`:
```xml
<service android:name="com.pravera.flutter_foreground_task.service.ForegroundService"
    android:foregroundServiceType="microphone" android:exported="false"/>
```
Set `compileSdk`/`targetSdk` to 34+ and `minSdkVersion` to 21+.

Set `serverUrl` in `mobile/lib/main.dart`. Add `RECORD_AUDIO`, `INTERNET`, `MODIFY_AUDIO_SETTINGS` permissions on Android and `NSMicrophoneUsageDescription` on iOS.
