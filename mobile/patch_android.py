"""Patches the generated Android project (run after `flutter create .`)."""
import re

p = 'android/app/src/main/AndroidManifest.xml'
s = open(p).read()

perms = ''.join(
    f'    <uses-permission android:name="android.permission.{n}"/>\n'
    for n in ['INTERNET', 'RECORD_AUDIO', 'MODIFY_AUDIO_SETTINGS', 'CAMERA', 'FOREGROUND_SERVICE',
              'FOREGROUND_SERVICE_MICROPHONE', 'POST_NOTIFICATIONS', 'WAKE_LOCK', 'ACCESS_NETWORK_STATE']
)
service = ('        <service android:name="com.pravera.flutter_foreground_task.service.ForegroundService"\n'
           '            android:foregroundServiceType="microphone" android:exported="false"/>\n')

if 'FOREGROUND_SERVICE_MICROPHONE' not in s:
    s = s.replace('<application', perms + '    <application', 1)
    s = s.replace('</application>', service + '    </application>', 1)
    # allow http:// servers for testing
    s = s.replace('<application', '<application android:usesCleartextTraffic="true"', 1)
    open(p, 'w').write(s)

g = 'android/app/build.gradle'
try:
    t = open(g).read()
    t = re.sub(r'minSdk(Version)?\s*=?\s*\S+', 'minSdk = 23', t, count=1)
    open(g, 'w').write(t)
except FileNotFoundError:
    g = 'android/app/build.gradle.kts'
    t = open(g).read()
    t = re.sub(r'minSdk\s*=\s*[^\n]+', 'minSdk = 23', t, count=1)
    open(g, 'w').write(t)
