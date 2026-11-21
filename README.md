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
Set `serverUrl` in `mobile/lib/main.dart`. Add `RECORD_AUDIO`, `INTERNET`, `MODIFY_AUDIO_SETTINGS` permissions on Android and `NSMicrophoneUsageDescription` on iOS.
