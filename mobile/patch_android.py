"""Patches the generated Android project (run after `flutter create .`)."""
import os
import re

FILEPATHS = '''<?xml version="1.0" encoding="utf-8"?>
<paths xmlns:android="http://schemas.android.com/apk/res/android">
    <files-path name="internal_apk_storage" path="ota_update/"/>
</paths>
'''

PERMISSIONS = ['INTERNET', 'RECORD_AUDIO', 'MODIFY_AUDIO_SETTINGS', 'CAMERA', 'FOREGROUND_SERVICE',
               'FOREGROUND_SERVICE_MICROPHONE', 'POST_NOTIFICATIONS', 'WAKE_LOCK', 'ACCESS_NETWORK_STATE',
               'REQUEST_INSTALL_PACKAGES']

SERVICE = '''        <service android:name="com.pravera.flutter_foreground_task.service.ForegroundService"
            android:foregroundServiceType="microphone" android:exported="false"/>
        <provider android:name="sk.fourq.otaupdate.OtaUpdateFileProvider"
            android:authorities="${applicationId}.ota_update_provider"
            android:exported="false" android:grantUriPermissions="true">
            <meta-data android:name="android.support.FILE_PROVIDER_PATHS" android:resource="@xml/filepaths"/>
        </provider>
'''

SIGNING = '''val keystorePath = System.getenv("KEYSTORE_PATH")
    signingConfigs {
        if (keystorePath != null) {
            create("release") {
                storeFile = file(keystorePath)
                storePassword = System.getenv("KEYSTORE_PASSWORD")
                keyAlias = System.getenv("KEY_ALIAS")
                keyPassword = System.getenv("KEYSTORE_PASSWORD")
            }
        }
    }

    buildTypes {'''


def patch_manifest():
    p = 'android/app/src/main/AndroidManifest.xml'
    s = open(p).read()
    if 'FOREGROUND_SERVICE_MICROPHONE' in s:
        return
    perms = ''.join(f'    <uses-permission android:name="android.permission.{n}"/>\n' for n in PERMISSIONS)
    s = s.replace('<application', perms + '    <application', 1)
    s = s.replace('</application>', SERVICE + '    </application>', 1)
    # allow http:// servers for testing
    s = s.replace('<application', '<application android:usesCleartextTraffic="true"', 1)
    open(p, 'w').write(s)


def patch_gradle():
    p = 'android/app/build.gradle.kts'
    s = open(p).read()

    def sub(pattern, repl):
        nonlocal s
        s, n = re.subn(pattern, lambda _: repl, s, count=1)
        assert n == 1, f'gradle patch failed: {pattern}'

    sub(r'minSdk\s*=\s*[^\n]+', 'minSdk = 23')
    # ota_update needs core library desugaring
    sub(r'compileOptions \{', 'compileOptions {\n        isCoreLibraryDesugaringEnabled = true')
    sub(r'buildTypes \{', SIGNING)
    sub(r'signingConfig = signingConfigs\.getByName\("debug"\)',
        'signingConfig = signingConfigs.findByName("release") ?: signingConfigs.getByName("debug")')
    s += '\ndependencies {\n    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.5")\n}\n'
    open(p, 'w').write(s)


def write_filepaths():
    # FileProvider paths used by ota_update to install the downloaded APK
    os.makedirs('android/app/src/main/res/xml', exist_ok=True)
    open('android/app/src/main/res/xml/filepaths.xml', 'w').write(FILEPATHS)


patch_manifest()
patch_gradle()
write_filepaths()
