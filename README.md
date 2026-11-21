# Walkie Talkie

Frequency-based push-to-talk app. Same frequency = same room. Range: 1.000 – 999.999 MHz (0.001 step, 3 decimals).

- `server.js` – Node + Socket.IO signaling server (WebRTC audio is peer-to-peer)
- `public/` – web client
- `mobile/` – Flutter mobile app

## Run
```
npm install && npm start
cd mobile && flutter create --platforms=android . && python3 patch_android.py && flutter run
```
`patch_android.py` adds the Android permissions, the foreground service (background mode) and the update installer. Set the server address in the app's "Server URL" field.

## Auto-update (Android)
Every CI build is published to the `latest` release (`walkie-talkie.apk` + `version.json`). The app checks it on start/resume and installs newer builds in-app.

Updates must be signed with the same key, so add these repo secrets (Settings > Secrets and variables > Actions):
- `KEYSTORE_BASE64` - base64 of the release keystore (alias `walkie`)
- `KEYSTORE_PASSWORD` - keystore (and key) password

Without them the workflow still builds but does not publish a release.
