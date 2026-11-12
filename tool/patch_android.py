"""Menyesuaikan folder android/ hasil `flutter create` untuk Jalan Bareng.

Dijalankan otomatis oleh GitHub Actions setelah `flutter create`. Aman dijalankan berulang.
"""
import pathlib
import re
import sys

root = pathlib.Path(__file__).resolve().parent.parent
android = root / "android"
if not android.exists():
    sys.exit("Folder android/ belum ada. Jalankan `flutter create --platforms=android .` dulu.")

# ---------- AndroidManifest ----------
manifest = android / "app/src/main/AndroidManifest.xml"
m = manifest.read_text()
perms = [
    "android.permission.INTERNET",
    "android.permission.POST_NOTIFICATIONS",
    "android.permission.RECEIVE_BOOT_COMPLETED",
    "android.permission.VIBRATE",
]
for p in perms:
    if p not in m:
        m = m.replace("<application", f'<uses-permission android:name="{p}"/>\n    <application', 1)
receivers = """
        <receiver android:exported="false" android:name="com.dexterous.flutterlocalnotifications.ScheduledNotificationReceiver" />
        <receiver android:exported="false" android:name="com.dexterous.flutterlocalnotifications.ScheduledNotificationBootReceiver">
            <intent-filter>
                <action android:name="android.intent.action.BOOT_COMPLETED"/>
                <action android:name="android.intent.action.MY_PACKAGE_REPLACED"/>
                <action android:name="android.intent.action.QUICKBOOT_POWERON" />
                <action android:name="com.htc.intent.action.QUICKBOOT_POWERON"/>
            </intent-filter>
        </receiver>
"""
if "ScheduledNotificationReceiver" not in m:
    m = m.replace("</application>", receivers + "    </application>", 1)
m = re.sub(r'android:label="[^"]*"', 'android:label="Jalan Bareng"', m, count=1)
manifest.write_text(m)

# ---------- app/build.gradle(.kts) ----------
groovy = android / "app/build.gradle"
kts = android / "app/build.gradle.kts"
if groovy.exists():
    g = groovy.read_text()
    g = re.sub(r"minSdk\s*=\s*flutter\.minSdkVersion", "minSdk = 23", g)
    g = re.sub(r"minSdkVersion\s+flutter\.minSdkVersion", "minSdkVersion 23", g)
    if "coreLibraryDesugaringEnabled" not in g:
        g = g.replace("compileOptions {", "compileOptions {\n        coreLibraryDesugaringEnabled true", 1)
    if "minifyEnabled false" not in g:
        g = re.sub(r"(signingConfig\s*=?\s*signingConfigs\.debug)", r"\1\n            minifyEnabled false\n            shrinkResources false", g, count=1)
    if "desugar_jdk_libs" not in g:
        g += "\ndependencies {\n    coreLibraryDesugaring 'com.android.tools:desugar_jdk_libs:2.1.4'\n}\n"
    groovy.write_text(g)
elif kts.exists():
    k = kts.read_text()
    k = re.sub(r"minSdk\s*=\s*flutter\.minSdkVersion", "minSdk = 23", k)
    if "isCoreLibraryDesugaringEnabled" not in k:
        k = k.replace("compileOptions {", "compileOptions {\n        isCoreLibraryDesugaringEnabled = true", 1)
    if "isMinifyEnabled = false" not in k:
        k = re.sub(r"(signingConfig\s*=\s*signingConfigs\.getByName\(\"debug\"\))", r"\1\n            isMinifyEnabled = false\n            isShrinkResources = false", k, count=1)
    if "desugar_jdk_libs" not in k:
        k += '\ndependencies {\n    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")\n}\n'
    kts.write_text(k)
else:
    sys.exit("android/app/build.gradle tidak ditemukan.")

print("Android config patched.")
