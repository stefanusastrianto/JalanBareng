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
media_perms = [
    "android.permission.READ_MEDIA_IMAGES",
    "android.permission.READ_MEDIA_VIDEO",
    "android.permission.READ_MEDIA_VISUAL_USER_SELECTED",
    "android.permission.ACCESS_MEDIA_LOCATION",
]
for p in perms + media_perms:
    if f'"{p}"' not in m:
        m = m.replace("<application", f'<uses-permission android:name="{p}"/>\n    <application', 1)
if '"android.permission.READ_EXTERNAL_STORAGE"' not in m:
    m = m.replace("<application", '<uses-permission android:name="android.permission.READ_EXTERNAL_STORAGE" android:maxSdkVersion="32"/>\n    <application', 1)
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
MEDIA3 = [
    "androidx.media3:media3-transformer:1.4.1",
    "androidx.media3:media3-effect:1.4.1",
    "androidx.media3:media3-common:1.4.1",
    "androidx.annotation:annotation-experimental:1.4.1",
]
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
    if "JB_KEYSTORE" not in g:
        g = g.replace("android {", """android {
    signingConfigs {
        debug {
            if (System.getenv("JB_KEYSTORE")) {
                storeFile file(System.getenv("JB_KEYSTORE"))
                storePassword "android"
                keyAlias "androiddebugkey"
                keyPassword "android"
            }
        }
    }""", 1)
    if "desugar_jdk_libs" not in g:
        g += "\ndependencies {\n    coreLibraryDesugaring 'com.android.tools:desugar_jdk_libs:2.1.4'\n" + "".join(f"    implementation '{d}'\n" for d in MEDIA3) + "}\n"
    groovy.write_text(g)
elif kts.exists():
    k = kts.read_text()
    k = re.sub(r"minSdk\s*=\s*flutter\.minSdkVersion", "minSdk = 23", k)
    if "isCoreLibraryDesugaringEnabled" not in k:
        k = k.replace("compileOptions {", "compileOptions {\n        isCoreLibraryDesugaringEnabled = true", 1)
    if "isMinifyEnabled = false" not in k:
        k = re.sub(r"(signingConfig\s*=\s*signingConfigs\.getByName\(\"debug\"\))", r"\1\n            isMinifyEnabled = false\n            isShrinkResources = false", k, count=1)
    if "JB_KEYSTORE" not in k:
        k = k.replace("android {", """android {
    signingConfigs {
        getByName("debug") {
            System.getenv("JB_KEYSTORE")?.let {
                storeFile = file(it)
                storePassword = "android"
                keyAlias = "androiddebugkey"
                keyPassword = "android"
            }
        }
    }""", 1)
    if "desugar_jdk_libs" not in k:
        k += '\ndependencies {\n    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")\n' + "".join(f'    implementation("{d}")\n' for d in MEDIA3) + '}\n'
    kts.write_text(k)
else:
    sys.exit("android/app/build.gradle tidak ditemukan.")

# ---------- MainActivity (kompres video + perakit recap) ----------
src = root / "tool/android/MainActivity.kt"
acts = list((android / "app/src/main").rglob("MainActivity.kt")) + list((android / "app/src/main").rglob("MainActivity.java"))
if not acts:
    sys.exit("MainActivity tidak ditemukan.")
target = android / "app/src/main/kotlin/id/jalanbareng/jalan_bareng/MainActivity.kt"
for a in acts:
    a.unlink()
target.parent.mkdir(parents=True, exist_ok=True)
target.write_text(src.read_text())

# ---------- ikon aplikasi dan ikon notifikasi ----------
import shutil
res_src = root / "tool/android/res"
res_dst = android / "app/src/main/res"
for f in res_src.rglob("*.png"):
    dst = res_dst / f.relative_to(res_src)
    dst.parent.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(f, dst)

print("Android config patched.")
