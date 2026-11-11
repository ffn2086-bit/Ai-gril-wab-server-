import glob
import os

if not os.path.exists("android"):
    os.system("flutter create . --platforms=android --force")

p = "android/app/src/main/AndroidManifest.xml"
if os.path.exists(p):
    s = open(p).read()
    perms = '''<uses-permission android:name="android.permission.INTERNET"/>
    <uses-permission android:name="android.permission.RECORD_AUDIO"/>
    <uses-permission android:name="android.permission.READ_EXTERNAL_STORAGE"/>
    <uses-permission android:name="android.permission.READ_MEDIA_IMAGES"/>
    <queries>
        <intent><action android:name="android.intent.action.TTS_SERVICE"/></intent>
        <intent><action android:name="android.speech.RecognitionService"/></intent>
    </queries>
    <application'''
    if "<uses-permission" not in s:
        s = s.replace("<application", perms, 1)
        open(p, "w").write(s)

for g in glob.glob("android/app/build.gradle*"):
    t = open(g).read()
    t = t.replace("flutter.minSdkVersion", "24")
    open(g, "w").write(t)

print("Patched successfully")
